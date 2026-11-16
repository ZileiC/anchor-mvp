"""System-instruction builder for the conversation adapters (SPEC §6.3 step 5).

The prompt contains only: role, name, language, reply-length hint, the eldercare
guidance, approved memories, and hard rules. Deleted or proposed memories never
reach it.

2026-11-16: the role used to hardcode the product's old placeholder name, so the
model introduced itself as "Anchor" no matter what the older adult called it. The
name now comes from ``preferences.assistant_name`` (My choices), falling back to
the product name, and the prompt tells the model to answer "who are you" with it.
"""

from __future__ import annotations

from typing import Any, Optional

from .eldercare_skill import guidance_lines

#: The product name, used when the senior has not named the companion themselves.
DEFAULT_NAME = "Everhere"

RULES = {
    "zh-CN": "只问一个问题。不诊断、不评分、不谈病情。回答要短，像聊天。",
    "en": "Ask at most one question. Never diagnose, score or discuss illness. Keep replies short.",
}


def companion_name(preferences: dict[str, Any]) -> str:
    """The name the older adult gave the companion, or the product name."""
    stored = (preferences.get("assistant_name") or "").strip()
    return stored or DEFAULT_NAME


def build_system_prompt(
    user: dict[str, Any],
    preferences: dict[str, Any],
    memories: list[dict[str, Any]],
    locale: Optional[str] = None,
) -> str:
    lang = "en" if (locale or user.get("locale")) == "en" else "zh-CN"
    name = companion_name(preferences)
    if lang == "en":
        lines = [
            f"You are {name}, a warm and patient voice companion for an older adult.",
            f"[NAME] The older adult calls you \"{name}\". If they ask who you are or "
            f"what your name is, answer with that name. Never mention another product "
            f"name or an older name for yourself.",
            "[LANG] en",
            "[SHORT] %d" % (1 if preferences.get("short_replies") else 0),
            "[PACE] %s" % preferences.get("voice_pace", "slow"),
            "[COMPANION_GUIDANCE]",
        ]
        lines.extend(f"- {line}" for line in guidance_lines("en"))
        if memories:
            lines.append("[MEMORY]")
            lines.extend(f"- {memory['fact']}" for memory in memories)
        lines.append("[RULES] " + RULES[lang])
        return "\n".join(lines)

    lines = [
        f"你是{name}，一位耐心、温和的语音陪伴者，陪老人聊日常。",
        f"[名字] 老人叫你「{name}」。被问到你是谁、你叫什么名字时，就用这个名字回答；"
        f"不要提别的产品名，也不要提你以前的旧名字。",
        "[语言] zh-CN",
        "[简短] %d" % (1 if preferences.get("short_replies") else 0),
        "[语速] %s" % preferences.get("voice_pace", "slow"),
        "[陪伴要点]",
    ]
    lines.extend(f"- {line}" for line in guidance_lines("zh-CN"))
    if memories:
        lines.append("[记忆]")
        lines.extend(f"- {memory['fact']}" for memory in memories)
    lines.append("[规则] " + RULES[lang])
    return "\n".join(lines)
