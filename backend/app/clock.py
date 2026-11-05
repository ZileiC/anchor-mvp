"""Injected clock plus timezone/window helpers.

Business code must never call datetime.now() directly (SPEC §2): schedules are
computed from the clock injected at application start, which tests replace.
"""
from __future__ import annotations

from datetime import datetime, time as dtime, timedelta, timezone
from typing import Union
from zoneinfo import ZoneInfo

ISO_FORMAT = "%Y-%m-%dT%H:%M:%SZ"


class Clock:
    def now(self) -> datetime:
        return datetime.now(timezone.utc)


class FakeClock(Clock):
    def __init__(self, moment: datetime | None = None) -> None:
        self._now = moment or datetime(2026, 11, 2, 1, 0, tzinfo=timezone.utc)

    def now(self) -> datetime:
        return self._now

    def set(self, moment: datetime) -> None:
        self._now = moment.astimezone(timezone.utc)

    def advance(self, **kwargs) -> None:
        self._now = self._now + timedelta(**kwargs)


def iso_utc(moment: datetime) -> str:
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=timezone.utc)
    return moment.astimezone(timezone.utc).strftime(ISO_FORMAT)


def parse_iso(value: str) -> datetime:
    text = value.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    moment = datetime.fromisoformat(text)
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=timezone.utc)
    return moment.astimezone(timezone.utc)


def parse_hhmm(value: str) -> dtime:
    if not isinstance(value, str) or len(value) != 5 or value[2] != ":":
        raise ValueError("Time must be HH:MM")
    hh, mm = value[:2], value[3:]
    if not (hh.isdigit() and mm.isdigit()):
        raise ValueError("Time must be HH:MM")
    hour, minute = int(hh), int(mm)
    if not (0 <= hour <= 23 and 0 <= minute <= 59):
        raise ValueError("Time must be HH:MM (00:00-23:59)")
    return dtime(hour=hour, minute=minute)


def _minutes(moment: datetime) -> int:
    return moment.hour * 60 + moment.minute


def _to_minutes(value: str) -> int:
    parsed = parse_hhmm(value)
    return parsed.hour * 60 + parsed.minute


def in_window(moment: datetime, start: str, end: str) -> bool:
    """True when ``moment`` (already local) is inside [start, end).

    A window whose end is before its start crosses midnight (quiet hours).
    """
    current = _minutes(moment)
    start_m = _to_minutes(start)
    end_m = _to_minutes(end)
    if start_m == end_m:
        return True
    if start_m < end_m:
        return start_m <= current < end_m
    return current >= start_m or current < end_m


def local_date_str(moment, timezone_name: str) -> str:
    """Accept either an aware datetime or a Clock (business code passes the clock)."""
    if not isinstance(moment, datetime) and hasattr(moment, "now"):
        moment = moment.now()
    try:
        zone = ZoneInfo(timezone_name)
    except Exception:  # pragma: no cover - stored timezones are validated upstream
        zone = ZoneInfo("Asia/Shanghai")
    return moment.astimezone(zone).date().isoformat()


def local_now(moment, timezone_name: str) -> datetime:
    if not isinstance(moment, datetime) and hasattr(moment, "now"):
        moment = moment.now()
    try:
        zone = ZoneInfo(timezone_name)
    except Exception:  # pragma: no cover
        zone = ZoneInfo("Asia/Shanghai")
    return moment.astimezone(zone)


DateLike = Union[datetime, str]
