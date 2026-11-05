#!/usr/bin/env python
"""Seed deterministic Anchor demo data (idempotent).

Run from ``anchor/backend`` with the project venv:

    ..\\.venv\\Scripts\\python.exe ..\\scripts\\seed_demo.py
    ..\\.venv\\Scripts\\python.exe ..\\scripts\\seed_demo.py --check

``--check`` seeds a throw-away temporary database, runs the seeder twice to prove
idempotency, generates the previous week's digest to prove the adequate-data rule
passes, prints a summary and deletes the temporary database. It never writes to
the configured ``ANCHOR_DB_PATH``.

The demo world: senior #1 林秀兰 (zh-CN, Asia/Shanghai) and caregiver #2 Mei with an
accepted relationship, explicit consents (all five sharing topics), two family
contacts, ten days of evidence-backed observations across the last three weeks, one
approved memory, a small activity-rotation history and the demo device id
designated device. No digest is pre-seeded: the worker generates it.
"""

from __future__ import annotations

import argparse
import json
import sys
import tempfile
from datetime import date, timedelta
from pathlib import Path
from typing import Any, Optional, Sequence

SCRIPTS_DIR = Path(__file__).resolve().parent
ANCHOR_DIR = SCRIPTS_DIR.parent
BACKEND_DIR = ANCHOR_DIR / "backend"
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from app.clock import Clock, iso_utc, local_now  # noqa: E402
from app.config import Settings  # noqa: E402
from app.context import AppContext  # noqa: E402
from app.db import Database  # noqa: E402

SENIOR_ID = 1
CAREGIVER_ID = 2
SENIOR_NAME = "林秀兰"
CAREGIVER_NAME = "Mei"
SENIOR_SUBJECT = "demo-senior-linxiulan"
CAREGIVER_SUBJECT = "demo-caregiver-mei"
TIMEZONE = "Asia/Shanghai"
LOCALE = "zh-CN"
DESIGNATED_DEVICE = "anchor-win-demo-1"  # matches AnchorConfig.deviceId in the desktop demo app
SHARE_TOPICS = ("participation", "activities", "mood", "meals", "wellbeing")
CONTACTS = (
    ("女儿 小梅", "13900001111"),
    ("鍎垮瓙 澶ф槑", "13800002222"),
)
MEMORY_FACT = "喜欢在阳台上种花。"

# (day offset from the previous ISO week's Monday, topic, evidence in the senior's words)
OBSERVATION_PLAN = (
    (0, "mood", "今天心情不错，和老朋友打了电话。"),
    (1, "meals", "中午吃了面条，胃口挺好。"),
    (2, "meals", "晚上喝了粥，配了点小菜。"),
    (3, "activities", "下午在阳台给花浇了水，还听了一会儿戏。"),
    (4, "activities", "玩了一局简单的棋，挺开心。"),
    (5, "participation", "和邻居聊了聊小区里的新花圃。"),
    (6, "participation", "女儿打电话来，聊了二十分钟。"),
    (-1, "mood", "这两天有点累，睡得早。"),
    (-2, "wellbeing", "今天量了血压，和平时差不多。"),
    (-3, "meals", "简单吃了点青菜和鱼。"),
    (-5, "wellbeing", "最近天气凉了，膝盖有点不舒服，但精神还好。"),
    (-6, "mood", "想起以前上班的事，笑了好一会儿。"),
    (-8, "participation", "和老同学说起了以前的春游。"),
)
ACTIVITY_ROTATION = (("trivia", 0), ("story", -1), ("memory", -1))


def _previous_iso_week(clock: Clock) -> tuple[date, date]:
    today = local_now(clock, TIMEZONE).date()
    this_monday = today - timedelta(days=today.weekday())
    return this_monday - timedelta(days=7), this_monday


def _ensure_users(ctx: AppContext) -> None:
    now = iso_utc(ctx.clock.now())
    rows = (
        (SENIOR_ID, "senior", SENIOR_NAME, SENIOR_SUBJECT),
        (CAREGIVER_ID, "caregiver", CAREGIVER_NAME, CAREGIVER_SUBJECT),
    )
    for user_id, role, name, subject in rows:
        ctx.db.execute(
            "INSERT INTO users(id, role, display_name, auth_subject, timezone, locale, created_at) "
            "VALUES (?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET role = excluded.role, "
            "display_name = excluded.display_name, timezone = excluded.timezone, "
            "locale = excluded.locale",
            (user_id, role, name, subject, TIMEZONE, LOCALE, now),
        )


def _ensure_relationship(ctx: AppContext) -> None:
    now = iso_utc(ctx.clock.now())
    ctx.db.execute(
        "INSERT INTO relationships(senior_id, caregiver_id, status, created_at, accepted_at) "
        "VALUES (?,?, 'accepted', ?, ?) ON CONFLICT(senior_id, caregiver_id) DO UPDATE SET "
        "status = 'accepted', accepted_at = excluded.accepted_at, revoked_at = NULL",
        (SENIOR_ID, CAREGIVER_ID, now, now),
    )


def _ensure_preferences(ctx: AppContext) -> None:
    ctx.preferences.get_or_create(SENIOR_ID)
    ctx.preferences.patch(
        SENIOR_ID,
        {
            "greeting_start": "09:00",
            "greeting_end": "11:00",
            "quiet_start": "21:00",
            "quiet_end": "08:00",
            "daily_cap": 1,
            "voice_pace": "slow",
            "short_replies": True,
            "language": LOCALE,
            "interests": ["园艺", "戏曲", "家常菜"],
            "designated_device_id": DESIGNATED_DEVICE,
            "digest_retention_days": 365,
        },
    )


def _ensure_contacts(ctx: AppContext) -> None:
    now = iso_utc(ctx.clock.now())
    for label, phone in CONTACTS:
        existing = ctx.db.query_one(
            "SELECT id FROM contacts WHERE senior_id = ? AND label = ? AND phone = ?",
            (SENIOR_ID, label, phone),
        )
        if existing is None:
            ctx.db.insert(
                "INSERT INTO contacts(senior_id, label, phone, is_family, created_at) "
                "VALUES (?,?,?,1,?)",
                (SENIOR_ID, label, phone, now),
            )


def _ensure_observations(ctx: AppContext) -> int:
    period_start, _ = _previous_iso_week(ctx.clock)
    inserted = 0
    for offset, topic, evidence in OBSERVATION_PLAN:
        event_date = (period_start + timedelta(days=offset)).isoformat()
        existing = ctx.db.query_one(
            "SELECT id FROM observations WHERE senior_id = ? AND event_date = ? "
            "AND source_ref = 'seed_demo'",
            (SENIOR_ID, event_date),
        )
        if existing is not None:
            continue
        ctx.db.insert(
            "INSERT INTO observations(senior_id, topic, event_date, evidence, source_ref, "
            "consent_version, created_at) VALUES (?,?,?,?,?,?,?)",
            (
                SENIOR_ID,
                topic,
                event_date,
                evidence,
                "seed_demo",
                ctx.consent.version(SENIOR_ID),
                iso_utc(ctx.clock.now()),
            ),
        )
        inserted += 1
    return inserted


def _ensure_memory(ctx: AppContext) -> None:
    existing = ctx.db.query_one(
        "SELECT id FROM memories WHERE senior_id = ? AND fact = ?", (SENIOR_ID, MEMORY_FACT)
    )
    if existing is None:
        now = iso_utc(ctx.clock.now())
        ctx.db.insert(
            "INSERT INTO memories(senior_id, fact, approval_state, approved_at, source_ref, "
            "created_at) VALUES (?,?, 'approved', ?, 'seed_demo', ?)",
            (SENIOR_ID, MEMORY_FACT, now, now),
        )


def _ensure_rotation(ctx: AppContext) -> None:
    now = iso_utc(ctx.clock.now())
    for activity_type, last_index in ACTIVITY_ROTATION:
        ctx.db.execute(
            "INSERT OR IGNORE INTO activity_rotation(senior_id, activity_type, last_index, "
            "updated_at) VALUES (?,?,?,?)",
            (SENIOR_ID, activity_type, last_index, now),
        )


def seed(ctx: AppContext) -> dict[str, Any]:
    """Create or top up the demo world; returns a summary of the final state."""
    _ensure_users(ctx)
    _ensure_relationship(ctx)
    ctx.consent.seed(
        SENIOR_ID,
        cloud_processing=True,
        proactive_invitations=True,
        record_observations=True,
        save_memory=True,
        share_topics=SHARE_TOPICS,
    )
    _ensure_preferences(ctx)
    _ensure_contacts(ctx)
    _ensure_observations(ctx)
    _ensure_memory(ctx)
    _ensure_rotation(ctx)

    db = ctx.db
    return {
        "users": int(db.scalar("SELECT COUNT(*) AS n FROM users") or 0),
        "relationship": db.query_one(
            "SELECT status FROM relationships WHERE senior_id = ? AND caregiver_id = ?",
            (SENIOR_ID, CAREGIVER_ID),
        )["status"],
        "consents": int(db.scalar("SELECT COUNT(*) AS n FROM consents WHERE senior_id = ?", (SENIOR_ID,)) or 0),
        "share_topics": ctx.consent.allowed_topics(SENIOR_ID),
        "contacts": int(db.scalar("SELECT COUNT(*) AS n FROM contacts WHERE senior_id = ?", (SENIOR_ID,)) or 0),
        "observations": int(
            db.scalar("SELECT COUNT(*) AS n FROM observations WHERE senior_id = ?", (SENIOR_ID,)) or 0
        ),
        "memories": int(db.scalar("SELECT COUNT(*) AS n FROM memories WHERE senior_id = ?", (SENIOR_ID,)) or 0),
        "activity_rotation": int(
            db.scalar("SELECT COUNT(*) AS n FROM activity_rotation WHERE senior_id = ?", (SENIOR_ID,)) or 0
        ),
        "designated_device_id": ctx.preferences.get_or_create(SENIOR_ID)["designated_device_id"],
    }


def _digest_preview(ctx: AppContext) -> dict[str, Any]:
    period_start, period_end = _previous_iso_week(ctx.clock)
    return ctx.digests.ensure_weekly_digest(
        SENIOR_ID, period_start.isoformat(), period_end.isoformat()
    )


def check(settings: Settings) -> int:
    """Seed a temporary database twice and validate; never touches the real DB."""
    with tempfile.TemporaryDirectory(prefix="anchor-demo-check-") as tmp:
        temp_settings = settings.with_(db_path=str(Path(tmp) / "demo-check.db"))
        database = Database(temp_settings.db_path)
        database.migrate()
        ctx = AppContext(temp_settings, database, Clock())
        try:
            first = seed(ctx)
            second = seed(ctx)
            problems: list[str] = []
            if first != second:
                problems.append(f"seeding is not idempotent: {first} != {second}")
            expected = {
                "users": 2,
                "contacts": 2,
                "observations": len(OBSERVATION_PLAN),
                "memories": 1,
                "activity_rotation": 3,
            }
            for key, value in expected.items():
                if second.get(key) != value:
                    problems.append(f"{key}: expected {value}, got {second.get(key)}")
            if second.get("relationship") != "accepted":
                problems.append("relationship is not accepted")
            if second.get("share_topics") != list(SHARE_TOPICS):
                problems.append(f"share topics incomplete: {second.get('share_topics')}")
            if second.get("designated_device_id") != DESIGNATED_DEVICE:
                problems.append("designated device missing")
            digest = _digest_preview(ctx)
            if digest["status"] != "draft" or not digest["items"]:
                problems.append(f"previous-week digest was not generated: {digest['status']}")

            print(f"demo senior #{SENIOR_ID} {SENIOR_NAME}; caregiver #{CAREGIVER_ID} {CAREGIVER_NAME}")
            print(json.dumps({**second, "digest_status": digest["status"]}, ensure_ascii=False))
            if problems:
                for problem in problems:
                    print(f"CHECK FAILED: {problem}", file=sys.stderr)
                return 1
            print("CHECK OK: demo data is idempotent and supports a weekly digest")
            return 0
        finally:
            ctx.close()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Seed Anchor demo data")
    parser.add_argument("--check", action="store_true", help="validate on a temp DB, write nothing")
    parser.add_argument("--db", default=None, help="override ANCHOR_DB_PATH")
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    settings = Settings.from_env()
    if args.db:
        settings = settings.with_(db_path=args.db)
    if args.check:
        return check(settings)

    database = Database(settings.db_path)
    database.migrate()
    ctx = AppContext(settings, database, Clock())
    try:
        summary = seed(ctx)
        summary["digest"] = _digest_preview(ctx)
        print(json.dumps(summary, ensure_ascii=False, indent=2))
        print(f"seeded demo data into {settings.db_path}")
        return 0
    finally:
        ctx.close()


if __name__ == "__main__":
    raise SystemExit(main())

