"""Curated activity pack: loading, deterministic rotation, session records (SPEC §6.5).

Rotation is persisted per ``(senior, type)`` in ``activity_rotation`` so an item
never repeats until every item of that type has been shown, across restarts.
"""

from __future__ import annotations

import json
from datetime import timedelta
from pathlib import Path
from typing import Any, Optional

from ..clock import Clock, iso_utc, parse_iso
from ..consent import ConsentService
from ..db import Database
from ..errors import AppError, validation_error
from ..paths import activities_content_path
from ..preferences import PreferencesService

# Kept for callers that import it; the engine resolves at construction time so a
# frozen bundle reads <sys._MEIPASS>/content/activities.json (see app/paths.py).
CONTENT_PATH = activities_content_path()
TYPES = ("trivia", "story", "memory")
MAX_DURATION_SECONDS = 7200


class ActivityEngine:
    def __init__(
        self,
        db: Database,
        clock: Clock,
        consent: Optional[ConsentService] = None,
        preferences: Optional[PreferencesService] = None,
        content_path: Optional[Path] = None,
    ) -> None:
        self.db = db
        self.clock = clock
        self.consent = consent or ConsentService(db, clock)
        self.preferences = preferences or PreferencesService(db, clock)
        self.content_path = Path(content_path) if content_path else activities_content_path()
        self._content: Optional[dict[str, Any]] = None

    # -- content ----------------------------------------------------------
    def content(self) -> dict[str, Any]:
        if self._content is None:
            self._content = json.loads(self.content_path.read_text(encoding="utf-8"))
        return self._content

    def all_items(self) -> list[dict[str, Any]]:
        return list(self.content()["activities"])

    def find(self, activity_id: str) -> Optional[dict[str, Any]]:
        for item in self.all_items():
            if item["id"] == activity_id:
                return item
        return None

    def items_of_type(self, activity_type: str) -> list[dict[str, Any]]:
        return [item for item in self.all_items() if item["type"] == activity_type]

    def localise(self, item: dict[str, Any], locale: str) -> dict[str, Any]:
        suffix = "_en" if locale == "en" else ""
        payload = {
            "id": item["id"],
            "type": item["type"],
            "title": item.get("title" + suffix) or item["title"],
            "prompt": item.get("prompt" + suffix) or item["prompt"],
            "minutes": item.get("minutes", 3),
        }
        if item.get("options"):
            payload["options"] = item.get("options" + suffix) or item["options"]
        if "answer" in item:
            payload["answer"] = item["answer"]
        return payload

    # -- rotation ---------------------------------------------------------
    def _last_index(self, senior_id: int, activity_type: str) -> tuple[int, str]:
        row = self.db.query_one(
            "SELECT last_index, updated_at FROM activity_rotation "
            "WHERE senior_id = ? AND activity_type = ?",
            (senior_id, activity_type),
        )
        if row is None:
            return -1, ""
        return int(row["last_index"]), str(row["updated_at"])

    def _set_last_index(self, senior_id: int, activity_type: str, index: int, at: str) -> None:
        self.db.execute(
            "INSERT INTO activity_rotation(senior_id, activity_type, last_index, updated_at) "
            "VALUES (?,?,?,?) ON CONFLICT(senior_id, activity_type) DO UPDATE SET "
            "last_index = excluded.last_index, updated_at = excluded.updated_at",
            (senior_id, activity_type, index, at),
        )

    def _rotation_stamp(self, senior_id: int) -> str:
        """Strictly increasing timestamp so type rotation is fair under a frozen clock."""
        now = iso_utc(self.clock.now())
        latest = self.db.scalar(
            "SELECT MAX(updated_at) FROM activity_rotation WHERE senior_id = ?", (senior_id,)
        )
        if latest and str(latest) >= now:
            return iso_utc(parse_iso(str(latest)) + timedelta(seconds=1))
        return now

    def _ordered_types(self, senior_id: int) -> list[str]:
        states = {activity_type: self._last_index(senior_id, activity_type) for activity_type in TYPES}
        return sorted(
            TYPES,
            key=lambda activity_type: (states[activity_type][1], TYPES.index(activity_type)),
        )

    def next_activity(self, senior_id: int) -> dict[str, Any]:
        for activity_type in self._ordered_types(senior_id):
            items = self.items_of_type(activity_type)
            if not items:
                continue
            last_index, _ = self._last_index(senior_id, activity_type)
            index = (last_index + 1) % len(items)
            return items[index]
        raise AppError("not_found", "No activities are available.")

    def rotation_ids(self, senior_id: int) -> list[str]:
        ids: list[str] = []
        for activity_type in self._ordered_types(senior_id):
            items = self.items_of_type(activity_type)
            if not items:
                continue
            last_index, _ = self._last_index(senior_id, activity_type)
            start = (last_index + 1) % len(items)
            ids.extend(items[(start + offset) % len(items)]["id"] for offset in range(len(items)))
        return ids

    # -- senior view ------------------------------------------------------
    def for_senior(self, senior_id: int) -> dict[str, Any]:
        senior = self.db.query_one("SELECT * FROM users WHERE id = ?", (senior_id,))
        locale = "en" if senior and senior["locale"] == "en" else "zh-CN"
        prefs = self.preferences.get_or_create(senior_id)
        interests = set(json.loads(prefs["interests"] or "[]"))
        items = [self.localise(item, locale) for item in self.all_items()]
        if interests:
            raw = {item["id"]: item for item in self.all_items()}
            matched = [
                payload
                for payload in items
                if interests & set(raw[payload["id"]].get("tags", []))
            ]
            if matched:
                matched_ids = {payload["id"] for payload in matched}
                items = [payload for payload in items if payload["id"] in matched_ids] + [
                    payload for payload in items if payload["id"] not in matched_ids
                ]
        return {"items": items, "rotation": self.rotation_ids(senior_id)}

    # -- sessions ---------------------------------------------------------
    def record_session(
        self,
        senior_id: int,
        activity_id: Any,
        completed: Any,
        duration_seconds: Any,
    ) -> dict[str, Any]:
        if not isinstance(activity_id, str) or not activity_id:
            raise validation_error("activity_id is required")
        if not isinstance(completed, bool):
            raise validation_error("completed must be true or false")
        if (
            not isinstance(duration_seconds, int)
            or isinstance(duration_seconds, bool)
            or not 0 <= duration_seconds <= MAX_DURATION_SECONDS
        ):
            raise validation_error(f"duration_seconds must be an integer 0..{MAX_DURATION_SECONDS}")
        item = self.find(activity_id)
        if item is None:
            raise AppError("not_found", "Activity not found.")
        stamp = self._rotation_stamp(senior_id)
        items = self.items_of_type(item["type"])
        index = next(position for position, row in enumerate(items) if row["id"] == activity_id)
        self._set_last_index(senior_id, item["type"], index, stamp)
        observation_recorded = self._record_observation(senior_id, item, duration_seconds)
        return {
            "recorded": True,
            "activity_id": activity_id,
            "observation_recorded": observation_recorded,
            "next_activity_id": self.next_activity(senior_id)["id"],
        }

    def _record_observation(self, senior_id: int, item: dict[str, Any], duration: int) -> bool:
        if not self.consent.is_allowed(senior_id, "record_observations"):
            return False
        prefs = self.preferences.get_or_create(senior_id)
        topics = json.loads(prefs["observation_topics"] or "[]")
        if "activities" not in topics:
            return False
        senior = self.db.query_one("SELECT timezone, locale FROM users WHERE id = ?", (senior_id,))
        from ..clock import local_date_str

        evidence = (
            f"Completed activity: {item['title']} ({duration}s)"
            if senior and senior["locale"] == "en"
            else f"完成了活动：{item['title']}（{duration}秒）"
        )
        self.db.execute(
            "INSERT INTO observations(senior_id, topic, event_date, evidence, source_ref, "
            "consent_version, created_at) VALUES (?,?,?,?,?,?,?)",
            (
                senior_id,
                "activities",
                local_date_str(self.clock, senior["timezone"] if senior else "Asia/Shanghai"),
                evidence[:140],
                item["id"],
                self.consent.version(senior_id),
                iso_utc(self.clock.now()),
            ),
        )
        return True
