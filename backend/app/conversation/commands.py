"""Deterministic command routing (SPEC §6.3 step 4).

Commands are recognised *before* the model so "stop" and "repeat" work instantly,
even when the network is slow or offline.
"""

from __future__ import annotations

import re
from typing import Any, Iterable, Optional

STOP_WORDS = ("别说了", "先别说了", "停止", "停下来", "安静", "quiet", "stop 停", "停", "stop")
REPEAT_WORDS = ("再说一遍", "再说一次", "重复一遍", "重复", "repeat")
PLAY_WORDS = ("游戏", "下棋", "玩", "play")
CALL_MARKERS = ("打电话", "通话", "call")

_CALL_PREFIXES = ("给", "帮", "call", "打给")


def normalise(text: str) -> str:
    return text.strip().lower()


def _contains_any(text: str, needles: Iterable[str]) -> bool:
    return any(needle in text for needle in needles)


def call_target(text: str) -> Optional[str]:
    """Extract the person to call, e.g. ``给儿子打电话`` -> ``儿子``."""
    lowered = text.lower()
    if "打电话" in text:
        before, after = text.split("打电话", 1)
        name = re.sub(r"^[给帮打]", "", before.strip()).strip(" ，,。.!！")
        if name:
            return name
        name = re.sub(r"^[给跟和]", "", after.strip()).strip(" ，,。.!！")
        return name or None
    if "通话" in text:
        before, after = text.split("通话", 1)
        name = re.sub(r"^[给帮打]", "", before.strip()).strip(" ，,。.!！")
        if name:
            return name
        name = re.sub(r"^[给跟和]", "", after.strip()).strip(" ，,。.!！")
        return name or None
    if lowered.startswith("call"):
        rest = text[4:].strip(" ,，。.!！")
        return rest or None
    return None


def route(text: str) -> Optional[dict[str, Any]]:
    """Return a command dict or ``None`` for ordinary conversation."""
    cleaned = normalise(text)
    if not cleaned:
        return None
    if _contains_any(cleaned, STOP_WORDS):
        return {"type": "stop"}
    if _contains_any(cleaned, REPEAT_WORDS):
        return {"type": "repeat"}
    if "call" in cleaned or "打电话" in cleaned or "通话" in cleaned:
        return {"type": "call", "target": call_target(text)}
    if _contains_any(cleaned, PLAY_WORDS):
        return {"type": "play"}
    return None


def match_contact(contacts: Iterable[dict[str, Any]], name: Optional[str]) -> Optional[dict[str, Any]]:
    """Resolve a spoken name against saved contacts (exact, then containment)."""
    if not name:
        return None
    wanted = name.strip().lower()
    if not wanted:
        return None
    rows = list(contacts)
    for row in rows:
        if str(row["label"]).strip().lower() == wanted:
            return row
    for row in rows:
        label = str(row["label"]).strip().lower()
        if wanted in label or label in wanted:
            return row
    return None
