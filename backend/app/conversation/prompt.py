"""System-instruction builder for the conversation adapters (SPEC §6.3 step 5).

The prompt contains only: role, language, reply-length hint, approved memories,
and hard rules. Deleted or proposed memories never reach it.
"""

from __future__ import annotations

from typing import Any, Optional

RULES = {
    "zh-CN": "只问一个问题。不诊断、不评分、不谈病情。回答要短，像聊天。",
    "en": "Ask at most one question. Never diagnose, score or discuss illness. Keep replies short.",
}


def build_system_prompt(
    user: dict[str, Any],
    preferences: dict[str, Any],
    memories: list[dict[str, Any]],
    locale: Optional[str] = None,
) -> str:
    lang = "en" if (locale or user.get("locale")) == "en" else "zh-CN"
    if lang == "en":
        lines = [
            "You are Anchor, a warm and patient voice companion for an older adult.",
            "[LANG] en",
            "[SHORT] %d" % (1 if preferences.get("short_replies") else 0),
            "[PACE] %s" % preferences.get("voice_pace", "slow"),
        ]
        if memories:
            lines.append("[MEMORY]")
            lines.extend(f"- {memory['fact']}" for memory in memories)
        lines.append("[RULES] " + RULES[lang])
        return "\n".join(lines)

    lines = [
        "你是 Anchor，一位耐心、温和的语音陪伴者，陪老人聊日常。",
        "[语言] zh-CN",
        "[简短] %d" % (1 if preferences.get("short_replies") else 0),
        "[语速] %s" % preferences.get("voice_pace", "slow"),
    ]
    if memories:
        lines.append("[记忆]")
        lines.extend(f"- {memory['fact']}" for memory in memories)
    lines.append("[规则] " + RULES[lang])
    return "\n".join(lines)
