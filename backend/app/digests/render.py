"""Deterministic, localised digest wording (SPEC §7.5/§7.6).

The MVP does not ask a model to rewrite digest items. Every sentence is a template
filled from counts the baseline module computed, so an item can never claim more
than the evidence supports. Each rendered item runs through
:mod:`app.digests.language_guard`; a template that ever contained diagnostic or
scoring language falls back to a neutral, still-supported sentence.
"""

from __future__ import annotations

from typing import Any, Iterable

from .language_guard import ensure_clean

LOCALES = ("zh-CN", "en")
DEFAULT_LOCALE = "zh-CN"

TOPIC_LABELS: dict[str, dict[str, str]] = {
    "participation": {"zh-CN": "你和我说了说话", "en": "how your days have been"},
    "activities": {"zh-CN": "你聊到了喜欢的活动", "en": "the activities you enjoy"},
    "mood": {"zh-CN": "你说到了心情", "en": "how you were feeling"},
    "meals": {"zh-CN": "你说到了吃饭", "en": "meals"},
    "wellbeing": {"zh-CN": "你说到了近况", "en": "how things are going"},
}

# Plain-language templates. ``{label}`` and ``{current_count}`` are the only slots;
# there is deliberately no free-text slot, so no unapproved wording can appear.
TEMPLATES: dict[str, dict[str, str]] = {
    "appeared": {
        "zh-CN": "这周有 {current_count} 天，{label}，前两周没有提到。可以找个机会问问。",
        "en": (
            "You talked about {label} on {current_count} days this week, after not mentioning "
            "it in the previous two weeks. It may be a good opening."
        ),
    },
    "changed_up": {
        "zh-CN": "这周有 {current_count} 天，{label}，比前两周多一些。可以问问最近怎么样。",
        "en": (
            "You talked about {label} on {current_count} days this week, more than in the "
            "previous two weeks. A gentle check-in may help."
        ),
    },
    "changed_down": {
        "zh-CN": "这周有 {current_count} 天，{label}，比前两周少一些。也许可以主动聊一聊。",
        "en": (
            "You talked about {label} on {current_count} days this week, fewer than in the "
            "previous two weeks. An open question could help."
        ),
    },
    "steady": {
        "zh-CN": "这周有 {current_count} 天，{label}，和之前差不多。",
        "en": "You talked about {label} on {current_count} days this week, about the same as before.",
    },
}

SAFE_FALLBACK = {
    "zh-CN": "这周有一些可以聊的小事。",
    "en": "There are a few small things to talk about this week.",
}

INSUFFICIENT_DATA = {
    "zh-CN": "这周的信息还不够，先不下结论。",
    "en": "There is not enough information this week to describe a change.",
}


def normalise_locale(locale: str | None) -> str:
    return "en" if locale == "en" else DEFAULT_LOCALE


def insufficient_message(locale: str | None) -> str:
    return INSUFFICIENT_DATA[normalise_locale(locale)]


def _template_key(candidate: dict[str, Any]) -> str:
    if int(candidate.get("baseline_count", 0)) == 0:
        return "appeared"
    delta = float(candidate.get("delta", 0.0))
    if delta > 0:
        return "changed_up"
    if delta < 0:
        return "changed_down"
    return "steady"


def render_item(candidate: dict[str, Any], locale: str | None = None) -> dict[str, Any]:
    """Render one candidate; the result always carries >= 1 evidence id."""
    lang = normalise_locale(locale)
    topic = str(candidate["topic"])
    label = TOPIC_LABELS.get(topic, {}).get(lang, topic)
    text = TEMPLATES[_template_key(candidate)][lang].format(
        label=label, current_count=int(candidate.get("current_count", 0))
    )
    text = ensure_clean(text, SAFE_FALLBACK[lang])
    evidence = [int(value) for value in candidate.get("evidence_ids", [])][:3]
    return {"topic": topic, "text": text, "evidence_ids": evidence}


def render_items(
    candidates: Iterable[dict[str, Any]], locale: str | None = None, limit: int = 3
) -> list[dict[str, Any]]:
    """Render up to ``limit`` supported items; three is a maximum, not a quota."""
    items: list[dict[str, Any]] = []
    for candidate in candidates:
        if len(items) >= limit:
            break
        item = render_item(candidate, locale)
        if not item["evidence_ids"]:
            continue
        items.append(item)
    return items


__all__ = [
    "DEFAULT_LOCALE",
    "INSUFFICIENT_DATA",
    "LOCALES",
    "SAFE_FALLBACK",
    "TEMPLATES",
    "TOPIC_LABELS",
    "insufficient_message",
    "normalise_locale",
    "render_item",
    "render_items",
]
