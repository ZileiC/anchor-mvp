"""Preferences read/patch with validation (SPEC §6.1).

The senior owns their settings; a caregiver may only *propose* changes through
``schedule_proposals`` (see ``relationships.py``).
"""

from __future__ import annotations

import json
from typing import Any, Optional

from .clock import Clock, iso_utc, parse_hhmm, parse_iso
from .consent import SHARE_TOPICS
from .db import Database
from .errors import validation_error

PATCHABLE_FIELDS = (
    "greeting_start",
    "greeting_end",
    "quiet_start",
    "quiet_end",
    "daily_cap",
    "paused",
    "snoozed_until",
    "voice_pace",
    "short_replies",
    "language",
    "interests",
    "observation_topics",
    "designated_device_id",
    "digest_retention_days",
)

LANGUAGES = ("zh-CN", "en")
VOICE_PACES = ("slow", "normal")


def _defaults(senior_id: int, now: str) -> dict[str, Any]:
    return {
        "senior_id": senior_id,
        "greeting_start": "09:00",
        "greeting_end": "11:00",
        "quiet_start": "21:00",
        "quiet_end": "08:00",
        "daily_cap": 1,
        "paused": 0,
        "snoozed_until": None,
        "voice_pace": "slow",
        "short_replies": 1,
        "language": "zh-CN",
        "interests": "[]",
        "observation_topics": json.dumps(list(SHARE_TOPICS)),
        "designated_device_id": None,
        "digest_retention_days": 365,
        "updated_at": now,
    }


def _as_hhmm(value: Any, field: str) -> str:
    if not isinstance(value, str):
        raise validation_error(f"{field} must be HH:MM")
    try:
        parse_hhmm(value)
    except ValueError as exc:
        raise validation_error(str(exc)) from exc
    return value


def _as_bool(value: Any, field: str) -> int:
    if not isinstance(value, bool):
        raise validation_error(f"{field} must be true or false")
    return 1 if value else 0


def _as_daily_cap(value: Any) -> int:
    if isinstance(value, bool):
        return 1 if value else 0
    if not isinstance(value, int) or value not in (0, 1):
        raise validation_error("daily_cap must be 0 or 1")
    return value


def _as_string_list(value: Any, field: str, allowed: Optional[tuple[str, ...]] = None) -> str:
    if not isinstance(value, list):
        raise validation_error(f"{field} must be a list of strings")
    out: list[str] = []
    for item in value:
        if not isinstance(item, str) or not item.strip():
            raise validation_error(f"{field} items must be non-empty strings")
        stripped = item.strip()
        if allowed is not None and stripped not in allowed:
            raise validation_error(
                f"{field} item {stripped!r} is not allowed", allowed=list(allowed)
            )
        if stripped not in out:
            out.append(stripped)
    if field == "interests" and len(out) > 10:
        raise validation_error("interests accepts at most 10 items")
    return json.dumps(out, ensure_ascii=False)


def validate_patch(updates: dict[str, Any]) -> dict[str, Any]:
    """Validate a preference patch and return storage-ready values."""
    if not isinstance(updates, dict):
        raise validation_error("Body must be an object.")
    unknown = [key for key in updates if key not in PATCHABLE_FIELDS]
    if unknown:
        raise validation_error(
            f"Unknown preference field(s): {', '.join(sorted(unknown))}",
            allowed=list(PATCHABLE_FIELDS),
        )
    values: dict[str, Any] = {}
    for field, value in updates.items():
        if field in ("greeting_start", "greeting_end", "quiet_start", "quiet_end"):
            values[field] = _as_hhmm(value, field)
        elif field == "daily_cap":
            values[field] = _as_daily_cap(value)
        elif field in ("paused", "short_replies"):
            values[field] = _as_bool(value, field)
        elif field == "snoozed_until":
            if value is None:
                values[field] = None
            elif isinstance(value, str):
                try:
                    values[field] = iso_utc(parse_iso(value))
                except ValueError as exc:
                    raise validation_error("snoozed_until must be an ISO-8601 timestamp") from exc
            else:
                raise validation_error("snoozed_until must be an ISO-8601 timestamp or null")
        elif field == "voice_pace":
            if value not in VOICE_PACES:
                raise validation_error(f"voice_pace must be one of {list(VOICE_PACES)}")
            values[field] = value
        elif field == "language":
            if value not in LANGUAGES:
                raise validation_error(f"language must be one of {list(LANGUAGES)}")
            values[field] = value
        elif field == "interests":
            values[field] = _as_string_list(value, "interests")
        elif field == "observation_topics":
            values[field] = _as_string_list(value, "observation_topics", SHARE_TOPICS)
        elif field == "designated_device_id":
            if value is None:
                values[field] = None
            elif isinstance(value, str) and 0 < len(value.strip()) <= 128:
                values[field] = value.strip()
            else:
                raise validation_error(
                    "designated_device_id must be a string up to 128 characters or null"
                )
        elif field == "digest_retention_days":
            if not isinstance(value, int) or isinstance(value, bool) or not 1 <= value <= 3650:
                raise validation_error("digest_retention_days must be an integer 1..3650")
            values[field] = value
    return values


class PreferencesService:
    def __init__(self, db: Database, clock: Clock) -> None:
        self.db = db
        self.clock = clock

    def get_or_create(self, senior_id: int) -> dict[str, Any]:
        row = self.db.query_one("SELECT * FROM preferences WHERE senior_id = ?", (senior_id,))
        if row is not None:
            return row
        now = iso_utc(self.clock.now())
        values = _defaults(senior_id, now)
        self.db.execute(
            "INSERT OR IGNORE INTO preferences(senior_id, greeting_start, greeting_end, quiet_start, "
            "quiet_end, daily_cap, paused, snoozed_until, voice_pace, short_replies, language, "
            "interests, observation_topics, designated_device_id, digest_retention_days, updated_at) "
            "VALUES (:senior_id, :greeting_start, :greeting_end, :quiet_start, :quiet_end, "
            ":daily_cap, :paused, :snoozed_until, :voice_pace, :short_replies, :language, "
            ":interests, :observation_topics, :designated_device_id, :digest_retention_days, "
            ":updated_at)",
            values,
        )
        return self.db.query_one("SELECT * FROM preferences WHERE senior_id = ?", (senior_id,))

    def patch(self, senior_id: int, updates: dict[str, Any]) -> dict[str, Any]:
        current = self.get_or_create(senior_id)
        values = validate_patch(updates)
        if not values:
            return {**current}
        values["updated_at"] = iso_utc(self.clock.now())
        assignments = ", ".join(f"{field} = :{field}" for field in values)
        self.db.execute(
            f"UPDATE preferences SET {assignments} WHERE senior_id = :senior_id",
            {**values, "senior_id": senior_id},
        )
        return self.db.query_one("SELECT * FROM preferences WHERE senior_id = ?", (senior_id,))
