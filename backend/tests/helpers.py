from __future__ import annotations

import json
from datetime import datetime, timezone
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
    "FailingLLM",
    "RecordingLLM",
    "StopDuringThinkingLLM",
    "headers",
    "insert_digest",
    "insert_job",
    "iso_now",
    "link_relationship",
    "make_user",
    "parse",
    "seed_consents",
    "token_for",
    "utc",
]
