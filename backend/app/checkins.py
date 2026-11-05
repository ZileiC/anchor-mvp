"""Proactive check-in eligibility, attempts and schedule (SPEC §6.2, S1/S7).

Rules (all must hold for eligibility): proactive consent, designated device,
inside the greeting window, outside quiet hours (which may cross midnight), not
paused, not snoozed, attempts today below the daily cap, and no active session.
"""

from __future__ import annotations

from datetime import date, datetime, timedelta
from typing import Any, Optional
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from .clock import Clock, in_window, iso_utc, parse_iso
from .consent import ConsentService
from .db import Database
from .errors import AppError, validation_error
from .preferences import PreferencesService

OUTCOMES = ("shown", "dismissed", "accepted", "no_response")

TEXTS = {
    "zh-CN": {
        "title": "早上好",
        "body": "今天想聊聊天吗？说一声就行。",
    },
    "en": {
        "title": "Good morning",
        "body": "Would you like to chat today? Just say hello.",
    },
}


def _zone(name: str) -> ZoneInfo:
    try:
        return ZoneInfo(name)
    except (ZoneInfoNotFoundError, ValueError):
        return ZoneInfo("Asia/Shanghai")


class CheckinService:
    def __init__(
        self,
        db: Database,
        clock: Clock,
        preferences: PreferencesService,
        consent: ConsentService,
    ) -> None:
        self.db = db
        self.clock = clock
        self.preferences = preferences
        self.consent = consent

    # -- helpers ----------------------------------------------------------
    def _senior(self, senior_id: int) -> dict[str, Any]:
        row = self.db.query_one("SELECT * FROM users WHERE id = ?", (senior_id,))
        if row is None:
            raise AppError("not_found", "Account not found.")
        return row

    def _prefs(self, senior_id: int) -> dict[str, Any]:
        return self.preferences.get_or_create(senior_id)

    def _now_local(self, senior_id: int) -> datetime:
        return self.clock.now().astimezone(_zone(self._senior(senior_id)["timezone"]))

    def _attempts_today(self, senior_id: int, local_date: str) -> int:
        return int(
            self.db.scalar(
                "SELECT COUNT(*) FROM checkin_events WHERE senior_id = ? AND local_date = ?",
                (senior_id, local_date),
                0,
            )
        )

    def _active_session(self, senior_id: int) -> Optional[dict[str, Any]]:
        return self.db.query_one(
            "SELECT * FROM sessions WHERE senior_id = ? AND state = 'active' "
            "ORDER BY started_at DESC LIMIT 1",
            (senior_id,),
        )

    def _snoozed(self, prefs: dict[str, Any]) -> bool:
        if not prefs["snoozed_until"]:
            return False
        try:
            return parse_iso(prefs["snoozed_until"]) > self.clock.now()
        except ValueError:  # pragma: no cover - stored values are validated
            return False

    def _designated_ok(self, prefs: dict[str, Any], device_id: Optional[str]) -> bool:
        designated = prefs["designated_device_id"]
        return bool(designated) and device_id is not None and device_id == designated

    # -- eligibility ------------------------------------------------------
    def eligibility(self, senior_id: int, device_id: Optional[str]) -> dict[str, Any]:
        prefs = self._prefs(senior_id)
        now_local = self._now_local(senior_id)
        local_date = now_local.date().isoformat()
        reasons: list[str] = []

        consent_ok = self.consent.is_allowed(senior_id, "proactive_invitations")
        if not consent_ok:
            reasons.append("consent_off")
        designated_ok = self._designated_ok(prefs, device_id)
        if not prefs["designated_device_id"]:
            reasons.append("no_designated_device")
        elif not designated_ok:
            reasons.append("designated_device_mismatch")
        if prefs["paused"]:
            reasons.append("paused")
        if self._snoozed(prefs):
            reasons.append("snoozed")
        attempts_today = self._attempts_today(senior_id, local_date)
        cap_remaining = max(0, int(prefs["daily_cap"]) - attempts_today)
        if cap_remaining <= 0:
            reasons.append("daily_cap_reached")
        if in_window(now_local, prefs["quiet_start"], prefs["quiet_end"]):
            reasons.append("quiet_hours")
        if not in_window(now_local, prefs["greeting_start"], prefs["greeting_end"]):
            reasons.append("outside_greeting_window")
        if self._active_session(senior_id) is not None:
            reasons.append("active_session")

        return {
            "eligible": not reasons,
            "reasons": reasons,
            "window": {"start": prefs["greeting_start"], "end": prefs["greeting_end"]},
            "quiet_hours": {"start": prefs["quiet_start"], "end": prefs["quiet_end"]},
            "cap_remaining": cap_remaining,
            "local_time": now_local.strftime("%H:%M"),
            "local_date": local_date,
            "designated_device_ok": designated_ok,
        }

    # -- attempts ---------------------------------------------------------
    def attempt(self, senior_id: int, device_id: Optional[str], outcome: str) -> dict[str, Any]:
        if outcome not in OUTCOMES:
            raise validation_error(f"outcome must be one of {list(OUTCOMES)}")
        prefs = self._prefs(senior_id)
        now_local = self._now_local(senior_id)
        local_date = now_local.date().isoformat()

        if not self.consent.is_allowed(senior_id, "proactive_invitations"):
            raise AppError(
                "consent_required", "Permission for check-ins has not been given.", status=409
            )
        if prefs["paused"]:
            raise AppError("conflict", "Check-ins are paused.", status=409)
        if self._snoozed(prefs):
            raise AppError("conflict", "Check-ins are snoozed.", status=409)
        if not prefs["designated_device_id"] or not self._designated_ok(prefs, device_id):
            raise AppError(
                "not_designated_device",
                "This device is not the one chosen for check-ins.",
                status=409,
            )
        attempts_today = self._attempts_today(senior_id, local_date)
        if attempts_today >= int(prefs["daily_cap"]):
            raise AppError("daily_cap_reached", "Today's check-in already happened.", status=409)
        if in_window(now_local, prefs["quiet_start"], prefs["quiet_end"]):
            raise AppError("quiet_hours", "It is quiet time now.", status=409)
        if not in_window(now_local, prefs["greeting_start"], prefs["greeting_end"]):
            raise AppError("outside_greeting_window", "Outside the greeting window.", status=409)
        session = self._active_session(senior_id)
        if session is not None:
            raise AppError(
                "conflict",
                "A conversation is already open.",
                status=409,
                session_id=session["id"],
            )

        self.db.execute(
            "INSERT INTO checkin_events(senior_id, device_id, local_date, outcome, created_at) "
            "VALUES (?,?,?,?,?)",
            (senior_id, device_id or "", local_date, outcome, iso_utc(self.clock.now())),
        )
        remaining = max(0, int(prefs["daily_cap"]) - (attempts_today + 1))
        return {
            "recorded": True,
            "outcome": outcome,
            "local_date": local_date,
            "cap_remaining": remaining,
        }

    # -- schedule ---------------------------------------------------------
    def schedule(self, senior_id: int) -> dict[str, Any]:
        prefs = self._prefs(senior_id)
        senior = self._senior(senior_id)
        locale = "en" if senior["locale"] == "en" else "zh-CN"
        texts = TEXTS[locale]
        now_local = self._now_local(senior_id)
        today: date = now_local.date()

        empty_reason: Optional[str] = None
        if not self.consent.is_allowed(senior_id, "proactive_invitations"):
            empty_reason = "consent_off"
        elif prefs["paused"]:
            empty_reason = "paused"
        elif self._snoozed(prefs):
            empty_reason = "snoozed"
        elif int(prefs["daily_cap"]) == 0:
            empty_reason = "daily_cap_zero"
        if empty_reason is not None:
            return {"entries": [], "note": empty_reason}

        attempts_today = self._attempts_today(senior_id, today.isoformat())
        note = ""
        if not prefs["designated_device_id"]:
            note = "no_designated_device"

        entries: list[dict[str, Any]] = []
        for offset in range(7):
            day = today + timedelta(days=offset)
            if offset == 0 and attempts_today >= int(prefs["daily_cap"]):
                continue
            local_time = prefs["greeting_start"]
            probe = datetime(
                day.year, day.month, day.day,
                int(local_time[:2]), int(local_time[3:]), tzinfo=now_local.tzinfo,
            )
            if in_window(probe, prefs["quiet_start"], prefs["quiet_end"]):
                local_time = prefs["quiet_end"]
            entries.append(
                {
                    "date": day.isoformat(),
                    "local_time": local_time,
                    "title": texts["title"],
                    "body": texts["body"],
                }
            )
        return {"entries": entries, "note": note}
