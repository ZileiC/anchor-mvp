"""Deterministic Anchor demo world: senior #1 林秀兰 and caregiver #2 Mei.

One idempotent seeder shared by both callers:

* ``scripts/seed_demo.py`` — the developer CLI (``--check`` validates it on a
  throw-away temporary database);
* ``app/entrypoint.py`` — the packaged ``anchor_backend.exe`` seeds an empty
  database on first start so the Windows demo runs with no Python installed.

``seed_demo`` takes ``(db, clock, settings)`` rather than an ``AppContext`` so the
frozen entry point can seed the live ``create_app`` database directly.

The demo world: senior #1 林秀兰 (zh-CN, Asia/Shanghai) and caregiver #2 Mei with an
accepted relationship, explicit consents (all five sharing topics), two family
contacts, ten days of evidence-backed observations across the last three weeks, one
approved memory, a small activity-rotation history and the demo device id
designated device. No digest is pre-seeded: the worker generates it.

Demo greeting window
--------------------
The packaged Windows demo is shown in the foreground at a table, so
``app/entrypoint.py`` seeds with ``demo_window=True``: the senior's greeting
window widens to **09:00–21:00** (quiet hours still start at 21:00), which is the
window documented in the demo package README. The developer CLI keeps the
historical 09:00–11:00 window unless it is called with ``--demo-window``, so the
normal seed behaviour (and every existing test/script) is unchanged.
"""

from __future__ import annotations

from datetime import date, timedelta
from typing import Any

from .clock import Clock, iso_utc, local_now
from .config import Settings
from .consent import ConsentService
from .db import Database
from .digests.service import DigestService
from .preferences import PreferencesService

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
    ("儿子 大明", "13800002222"),
)
MEMORY_FACT = "喜欢在阳台上种花。"
SOURCE_REF = "seed_demo"

NORMAL_GREETING_WINDOW = ("09:00", "11:00")
DEMO_GREETING_WINDOW = ("09:00", "21:00")

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


class _DemoWorld:
    """The demo seed with the few services it needs (no AppContext/providers)."""

    def __init__(self, db: Database, clock: Clock, settings: Settings) -> None:
        self.db = db
        self.clock = clock
        self.timezone = settings.timezone or TIMEZONE
        self.consent = ConsentService(db, clock)
        self.preferences = PreferencesService(db, clock)
        self.digests = DigestService(db, clock, self.consent)

    # -- dates ------------------------------------------------------------
    def previous_iso_week(self) -> tuple[date, date]:
        today = local_now(self.clock, self.timezone).date()
        this_monday = today - timedelta(days=today.weekday())
        return this_monday - timedelta(days=7), this_monday

    # -- rows -------------------------------------------------------------
    def _ensure_users(self) -> None:
        now = iso_utc(self.clock.now())
        rows = (
            (SENIOR_ID, "senior", SENIOR_NAME, SENIOR_SUBJECT),
            (CAREGIVER_ID, "caregiver", CAREGIVER_NAME, CAREGIVER_SUBJECT),
        )
        for user_id, role, name, subject in rows:
            self.db.execute(
                "INSERT INTO users(id, role, display_name, auth_subject, timezone, locale, created_at) "
                "VALUES (?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET role = excluded.role, "
                "display_name = excluded.display_name, timezone = excluded.timezone, "
                "locale = excluded.locale",
                (user_id, role, name, subject, self.timezone, LOCALE, now),
            )

    def _ensure_relationship(self) -> None:
        now = iso_utc(self.clock.now())
        self.db.execute(
            "INSERT INTO relationships(senior_id, caregiver_id, status, created_at, accepted_at) "
            "VALUES (?,?, 'accepted', ?, ?) ON CONFLICT(senior_id, caregiver_id) DO UPDATE SET "
            "status = 'accepted', accepted_at = excluded.accepted_at, revoked_at = NULL",
            (SENIOR_ID, CAREGIVER_ID, now, now),
        )

    def _ensure_preferences(self, demo_window: bool) -> None:
        greeting_start, greeting_end = (
            DEMO_GREETING_WINDOW if demo_window else NORMAL_GREETING_WINDOW
        )
        self.preferences.get_or_create(SENIOR_ID)
        self.preferences.patch(
            SENIOR_ID,
            {
                "greeting_start": greeting_start,
                "greeting_end": greeting_end,
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

    def _ensure_contacts(self) -> None:
        now = iso_utc(self.clock.now())
        for label, phone in CONTACTS:
            existing = self.db.query_one(
                "SELECT id FROM contacts WHERE senior_id = ? AND label = ? AND phone = ?",
                (SENIOR_ID, label, phone),
            )
            if existing is None:
                self.db.insert(
                    "INSERT INTO contacts(senior_id, label, phone, is_family, created_at) "
                    "VALUES (?,?,?,1,?)",
                    (SENIOR_ID, label, phone, now),
                )

    def _ensure_observations(self) -> int:
        period_start, _ = self.previous_iso_week()
        inserted = 0
        for offset, topic, evidence in OBSERVATION_PLAN:
            event_date = (period_start + timedelta(days=offset)).isoformat()
            existing = self.db.query_one(
                "SELECT id FROM observations WHERE senior_id = ? AND event_date = ? "
                "AND source_ref = ?",
                (SENIOR_ID, event_date, SOURCE_REF),
            )
            if existing is not None:
                continue
            self.db.insert(
                "INSERT INTO observations(senior_id, topic, event_date, evidence, source_ref, "
                "consent_version, created_at) VALUES (?,?,?,?,?,?,?)",
                (
                    SENIOR_ID,
                    topic,
                    event_date,
                    evidence,
                    SOURCE_REF,
                    self.consent.version(SENIOR_ID),
                    iso_utc(self.clock.now()),
                ),
            )
            inserted += 1
        return inserted

    def _ensure_memory(self) -> None:
        existing = self.db.query_one(
            "SELECT id FROM memories WHERE senior_id = ? AND fact = ?", (SENIOR_ID, MEMORY_FACT)
        )
        if existing is None:
            now = iso_utc(self.clock.now())
            self.db.insert(
                "INSERT INTO memories(senior_id, fact, approval_state, approved_at, source_ref, "
                "created_at) VALUES (?,?, 'approved', ?, ?, ?)",
                (SENIOR_ID, MEMORY_FACT, now, SOURCE_REF, now),
            )

    def _ensure_rotation(self) -> None:
        now = iso_utc(self.clock.now())
        for activity_type, last_index in ACTIVITY_ROTATION:
            self.db.execute(
                "INSERT OR IGNORE INTO activity_rotation(senior_id, activity_type, last_index, "
                "updated_at) VALUES (?,?,?,?)",
                (SENIOR_ID, activity_type, last_index, now),
            )

    # -- public -----------------------------------------------------------
    def seed(self, demo_window: bool = False) -> dict[str, Any]:
        """Create or top up the demo world; returns a summary of the final state."""
        self._ensure_users()
        self._ensure_relationship()
        self.consent.seed(
            SENIOR_ID,
            cloud_processing=True,
            proactive_invitations=True,
            record_observations=True,
            save_memory=True,
            share_topics=SHARE_TOPICS,
        )
        self._ensure_preferences(demo_window)
        self._ensure_contacts()
        self._ensure_observations()
        self._ensure_memory()
        self._ensure_rotation()

        db = self.db
        return {
            "users": int(db.scalar("SELECT COUNT(*) AS n FROM users") or 0),
            "relationship": db.query_one(
                "SELECT status FROM relationships WHERE senior_id = ? AND caregiver_id = ?",
                (SENIOR_ID, CAREGIVER_ID),
            )["status"],
            "consents": int(
                db.scalar("SELECT COUNT(*) AS n FROM consents WHERE senior_id = ?", (SENIOR_ID,)) or 0
            ),
            "share_topics": self.consent.allowed_topics(SENIOR_ID),
            "contacts": int(
                db.scalar("SELECT COUNT(*) AS n FROM contacts WHERE senior_id = ?", (SENIOR_ID,)) or 0
            ),
            "observations": int(
                db.scalar("SELECT COUNT(*) AS n FROM observations WHERE senior_id = ?", (SENIOR_ID,))
                or 0
            ),
            "memories": int(
                db.scalar("SELECT COUNT(*) AS n FROM memories WHERE senior_id = ?", (SENIOR_ID,)) or 0
            ),
            "activity_rotation": int(
                db.scalar(
                    "SELECT COUNT(*) AS n FROM activity_rotation WHERE senior_id = ?", (SENIOR_ID,)
                )
                or 0
            ),
            "designated_device_id": self.preferences.get_or_create(SENIOR_ID)["designated_device_id"],
        }

    def weekly_digest(self) -> dict[str, Any]:
        """Generate (or read back) the previous ISO week's digest for the demo senior."""
        period_start, period_end = self.previous_iso_week()
        return self.digests.ensure_weekly_digest(
            SENIOR_ID, period_start.isoformat(), period_end.isoformat()
        )


def seed_demo(
    db: Database,
    clock: Clock,
    settings: Settings,
    *,
    demo_window: bool = False,
) -> dict[str, Any]:
    """Create or top up the demo world; returns a summary of the final state.

    Idempotent: every row is upserted or looked up first, so calling it twice is
    a no-op (``scripts/seed_demo.py --check`` proves this on a temp database).
    """
    return _DemoWorld(db, clock, settings).seed(demo_window=demo_window)


def weekly_digest(db: Database, clock: Clock, settings: Settings) -> dict[str, Any]:
    """Ensure the previous ISO week's digest exists for the demo senior."""
    return _DemoWorld(db, clock, settings).weekly_digest()
