"""Diagnostic-language detector (SPEC §7.6).

One shared guard for generated dialogue and digest items: nothing that diagnoses,
scores or predicts may be shown to the senior or their family.
"""

from __future__ import annotations

from typing import Iterable, Optional

BANNED_PATTERNS: tuple[str, ...] = (
    "诊断",
    "痴呆",
    "认知",
    "抑郁",
    "评分",
    "分数",
    "健康分",
    "预警",
    "退化",
    "dementia",
    "diagnosis",
    "diagnose",
    "cognitive",
    "depression",
    "score",
    "risk level",
)


def find_banned(text: str) -> list[str]:
    if not isinstance(text, str):
        return []
    lowered = text.lower()
    return [pattern for pattern in BANNED_PATTERNS if pattern in lowered]


def is_clean(text: str) -> bool:
    return not find_banned(text)


def ensure_clean(text: str, fallback: str) -> str:
    """Return ``fallback`` when ``text`` contains diagnostic language."""
    return text if is_clean(text) else fallback


def first_banned(texts: Iterable[str]) -> Optional[str]:
    for text in texts:
        found = find_banned(text)
        if found:
            return found[0]
    return None
