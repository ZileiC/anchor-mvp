from __future__ import annotations

import json
from datetime import date, datetime, timedelta, timezone
from typing import Any, Optional

from app.auth import issue_token
from app.clock import iso_utc, parse_iso
from app.errors import AppError, provider_unavailable


def headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def token_for(app, user: dict[str, Any]) -> str:
    ctx = app.state.ctx
    token, _ = issue_token(ctx.settings, int(user["id"]), str(user["role"]), ctx.clock)
    return token


def make_user(app, role: str, display_name: str, subject: Optional[str] = None) -> dict[str, Any]:
    ctx = app.state.ctx
    now = iso_utc(ctx.clock.now())
    user_id = ctx.db.insert(
        "INSERT INTO users(role, display_name, auth_subject, timezone, locale, created_at) "
        "VALUES (?,?,?,?,?,?)",
        (
            role,
            display_name,
            subject or f"{role}-{display_name}-{now}-{ctx.db.scalar('SELECT COUNT(*) AS n FROM users')}",
            "Asia/Shanghai",
            "zh-CN",
            now,
        ),
    )
    return ctx.db.query_one("SELECT * FROM users WHERE id = ?", (user_id,))


def seed_consents(
    app,
    senior: dict[str, Any],
    *,
    cloud_processing: bool = False,
    proactive_invitations: bool = False,
    save_memory: bool = False,
    record_observations: bool = False,
    share_topics: tuple[str, ...] = (),
) -> None:
    """Write explicit consent rows (default private, version stays at 1)."""
    ctx = app.state.ctx
    senior_id = int(senior["id"])
    version = ctx.consent.version(senior_id)
    now = iso_utc(ctx.clock.now())
    rows: list[tuple[str, str, bool]] = [
        ("cloud_processing", "", cloud_processing),
        ("proactive_invitations", "", proactive_invitations),
        ("save_memory", "", save_memory),
        ("record_observations", "", record_observations),
    ]
    for topic in ("participation", "activities", "mood", "meals", "wellbeing"):
        rows.append(("share_topic", topic, topic in share_topics))
    with ctx.db.tx() as conn:
        for capability, topic, allowed in rows:
            conn.execute(
                "INSERT INTO consents(senior_id, capability, topic, allowed, version, updated_at) "
                "VALUES (?,?,?,?,?,?) "
                "ON CONFLICT(senior_id, capability, topic) DO UPDATE SET "
                "allowed = excluded.allowed, version = excluded.version, "
                "updated_at = excluded.updated_at",
                (senior_id, capability, topic, 1 if allowed else 0, version, now),
            )


def link_relationship(
    app,
    senior: dict[str, Any],
    caregiver: dict[str, Any],
    *,
    status: str = "accepted",
) -> dict[str, Any]:
    ctx = app.state.ctx
    now = iso_utc(ctx.clock.now())
    existing = ctx.db.query_one(
        "SELECT * FROM relationships WHERE senior_id = ? AND caregiver_id = ?",
        (int(senior["id"]), int(caregiver["id"])),
    )
    accepted_at = now if status == "accepted" else None
    revoked_at = now if status == "revoked" else None
    if existing:
        ctx.db.execute(
            "UPDATE relationships SET status = ?, accepted_at = ?, revoked_at = ? WHERE id = ?",
            (status, accepted_at, revoked_at, existing["id"]),
        )
        relationship_id = int(existing["id"])
    else:
        relationship_id = ctx.db.insert(
            "INSERT INTO relationships(senior_id, caregiver_id, status, created_at, accepted_at) "
            "VALUES (?,?,?,?,?)",
            (int(senior["id"]), int(caregiver["id"]), status, now, accepted_at),
        )
    return ctx.db.query_one("SELECT * FROM relationships WHERE id = ?", (relationship_id,))


def insert_digest(
    app,
    senior: dict[str, Any],
    *,
    status: str = "approved",
    period_start: str = "2026-01-05",
    items: Optional[list[dict[str, Any]]] = None,
) -> int:
    ctx = app.state.ctx
    now = iso_utc(ctx.clock.now())
    return ctx.db.insert(
        "INSERT INTO digests(senior_id, period_start, period_end, status, items_json, "
        "consent_version, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?)",
        (
            int(senior["id"]),
            period_start,
            "2026-01-12",
            status,
            json.dumps(items or [], ensure_ascii=False),
            ctx.consent.version(int(senior["id"])),
            now,
            now,
        ),
    )


def insert_contact(
    app,
    senior: dict[str, Any],
    *,
    label: str = "小梅",
    phone: str = "+8613900001111",
    is_family: int = 1,
) -> int:
    ctx = app.state.ctx
    return ctx.db.insert(
        "INSERT INTO contacts(senior_id, label, phone, is_family, created_at) "
        "VALUES (?,?,?,?,?)",
        (int(senior["id"]), label, phone, is_family, iso_utc(ctx.clock.now())),
    )


def insert_notification(
    app,
    user: dict[str, Any],
    *,
    kind: str = "digest_ready",
    title: str = "提醒",
    body: str = "有新的内容可以查看。",
) -> int:
    ctx = app.state.ctx
    return ctx.db.insert(
        "INSERT INTO notifications(user_id, kind, title, body, created_at) VALUES (?,?,?,?,?)",
        (int(user["id"]), kind, title, body, iso_utc(ctx.clock.now())),
    )


def insert_job(app, job_type: str, payload: dict[str, Any], idempotency_key: str) -> int:
    ctx = app.state.ctx
    now = iso_utc(ctx.clock.now())
    return ctx.db.insert(
        "INSERT INTO jobs(job_type, payload_json, due_at, status, idempotency_key, "
        "created_at, updated_at) VALUES (?,?,?, 'pending', ?, ?, ?)",
        (
            job_type,
            json.dumps(payload, ensure_ascii=False),
            now,
            idempotency_key,
            now,
            now,
        ),
    )


DIGEST_PERIOD_START = "2025-12-29"  # previous ISO week for the default fake clock
DIGEST_PERIOD_END = "2026-01-05"


def insert_observation(
    app,
    senior: dict[str, Any],
    *,
    topic: str = "participation",
    event_date: str = DIGEST_PERIOD_START,
    evidence: str = "今天聊了聊天。",
    source_ref: Optional[str] = None,
    consent_version: Optional[int] = None,
) -> int:
    ctx = app.state.ctx
    senior_id = int(senior["id"])
    return ctx.db.insert(
        "INSERT INTO observations(senior_id, topic, event_date, evidence, source_ref, "
        "consent_version, created_at) VALUES (?,?,?,?,?,?,?)",
        (
            senior_id,
            topic,
            event_date,
            evidence,
            source_ref,
            consent_version if consent_version is not None else ctx.consent.version(senior_id),
            iso_utc(ctx.clock.now()),
        ),
    )


def seed_adequate_observations(
    app,
    senior: dict[str, Any],
    *,
    topic: str = "mood",
    evidence: str = "今天聊到了心情。",
    period_start: str = DIGEST_PERIOD_START,
    current_offsets: tuple[int, ...] = (0, 1, 2, 3),
    prior_offsets: tuple[int, ...] = (1, 2, 3, 4, 5, 6),
) -> list[int]:
    """4 current-period days + 6 prior-14-day days: the adequate-data rule passes."""
    start = date.fromisoformat(period_start)
    observation_ids: list[int] = []
    for offset in current_offsets:
        observation_ids.append(
            insert_observation(
                app,
                senior,
                topic=topic,
                event_date=(start + timedelta(days=offset)).isoformat(),
                evidence=evidence,
            )
        )
    for offset in prior_offsets:
        observation_ids.append(
            insert_observation(
                app,
                senior,
                topic=topic,
                event_date=(start - timedelta(days=offset)).isoformat(),
                evidence=evidence,
            )
        )
    return observation_ids


class RecordingLLM:
    """Test double that records every prompt it received."""

    def __init__(self, reply_text: str = "好呀。") -> None:
        self.reply_text = reply_text
        self.calls: list[dict[str, Any]] = []

    def reply(self, system: str, turns: list[dict[str, str]], max_words: int = 30) -> str:
        self.calls.append({"system": system, "turns": list(turns), "max_words": max_words})
        return self.reply_text


class FailingLLM:
    def reply(self, system: str, turns: list[dict[str, str]], max_words: int = 30) -> str:
        raise provider_unavailable("The conversation service is unavailable.")


class StopDuringThinkingLLM:
    """Stops the session from inside the model call, then returns a late reply."""

    def __init__(self, app, session_id: str, senior_id: int) -> None:
        self.app = app
        self.session_id = session_id
        self.senior_id = senior_id
        self.calls = 0

    def reply(self, system: str, turns: list[dict[str, str]], max_words: int = 30) -> str:
        self.calls += 1
        ctx = self.app.state.ctx
        now = iso_utc(ctx.clock.now())
        with ctx.db.tx() as conn:
            conn.execute(
                "UPDATE sessions SET state = 'stopped', ended_at = ? WHERE id = ?",
                (now, self.session_id),
            )
            conn.execute("DELETE FROM turns WHERE session_id = ?", (self.session_id,))
        return "我来晚了，这句不该出现。"


def iso_now(app) -> str:
    return iso_utc(app.state.ctx.clock.now())


def parse(value: str) -> datetime:
    return parse_iso(value)


def utc(*args, **kwargs) -> datetime:  # small convenience for tests
    return datetime(*args, tzinfo=timezone.utc, **kwargs)


__all__ = [
    "AppError",
    "DIGEST_PERIOD_END",
    "DIGEST_PERIOD_START",
    "FailingLLM",
    "RecordingLLM",
    "StopDuringThinkingLLM",
    "headers",
    "insert_contact",
    "insert_digest",
    "insert_job",
    "insert_notification",
    "insert_observation",
    "iso_now",
    "link_relationship",
    "make_user",
    "parse",
    "seed_adequate_observations",
    "seed_consents",
    "token_for",
    "utc",
]
