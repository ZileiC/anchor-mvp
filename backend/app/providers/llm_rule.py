"""Offline deterministic dialogue engine (default provider, SPEC §2).

It paraphrases nothing: it acknowledges, asks at most one question, and can echo an
approved memory when the older adult's words overlap it. This keeps the MVP demo
working with no network and makes every reply assertable in tests.
"""

from __future__ import annotations

import re
from typing import Optional

SAFE_FALLBACK = {
    "zh-CN": "我在呢，慢慢说就好。",
    "en": "I am here. Take your time.",
}

MEMORY_REPLY = {
    "zh-CN": "我记得你说过：{fact}。现在还想聊聊这个吗？",
    "en": "I remember you told me: {fact}. Would you like to talk about that?",
}

TEMPLATES: dict[str, list[str]] = {
    "zh-CN": [
        "我在听着呢。今天有没有什么想说的？",
        "嗯，我听到了。今天过得怎么样？",
        "好呀，我陪你聊会儿。今天最想做点什么？",
    ],
    "en": [
        "I'm listening. Is there something you would like to talk about today?",
        "Mm, I hear you. How has your day been?",
        "All right, let's chat for a while. What would you like to do today?",
    ],
}

TOPICS = {
    "meal": {
        "zh-CN": ["吃", "饭", "菜", "喝"],
        "en": ["eat", "meal", "food", "lunch", "dinner", "breakfast"],
        "reply": {
            "zh-CN": "饭菜还合口吗？今天吃了些什么？",
            "en": "Did you enjoy your meal? What did you have today?",
        },
    },
    "mood": {
        "zh-CN": ["心情", "高兴", "开心", "累", "难过", "烦"],
        "en": ["happy", "sad", "tired", "mood", "lonely"],
        "reply": {
            "zh-CN": "我在这儿陪着你。今天最想做什么？",
            "en": "I am here with you. What would you most like to do today?",
        },
    },
    "activity": {
        "zh-CN": ["玩", "游戏", "下棋", "唱", "散步"],
        "en": ["play", "game", "chess", "walk", "sing"],
        "reply": {
            "zh-CN": "好啊，想玩点什么？",
            "en": "Good idea. What would you like to play?",
        },
    },
}


def language_of(system: str) -> str:
    return "en" if re.search(r"\[(?:语言|LANG)\]\s*en", system) else "zh-CN"


def memory_facts(system: str) -> list[str]:
    """Extract the approved-memory bullet list from a built system prompt."""
    facts: list[str] = []
    in_block = False
    for line in system.splitlines():
        stripped = line.strip()
        if stripped in ("[记忆]", "[MEMORY]"):
            in_block = True
            continue
        if in_block:
            if stripped.startswith("[") and stripped.endswith("]"):
                break
            if stripped.startswith("- "):
                facts.append(stripped[2:].strip())
    return facts


def _longest_common(a: str, b: str) -> int:
    best = 0
    for i in range(len(a)):
        for j in range(i + best + 1, len(a) + 1):
            if a[i:j] in b:
                best = j - i
            else:
                break
    return best


def best_memory(utterance: str, facts: list[str]) -> Optional[str]:
    best: Optional[str] = None
    best_score = 1
    for fact in facts:
        score = _longest_common(fact, utterance)
        if score > best_score:
            best, best_score = fact, score
    return best


class RuleLLM:
    """Deterministic, network-free dialogue adapter."""

    def __init__(self, turn_counter_start: int = 0) -> None:
        self._calls = turn_counter_start

    def reply(self, system: str, turns: list[dict[str, str]], max_words: int = 30) -> str:
        self._calls += 1
        lang = language_of(system)
        utterance = ""
        for turn in reversed(turns):
            if turn.get("role") == "user":
                utterance = turn.get("content", "")
                break
        if not utterance.strip():
            return SAFE_FALLBACK[lang]
        fact = best_memory(utterance, memory_facts(system))
        if fact:
            return MEMORY_REPLY[lang].format(fact=fact)
        lowered = utterance.lower()
        for topic in ("meal", "mood", "activity"):
            keywords = TOPICS[topic][lang]
            if any(keyword in utterance or keyword in lowered for keyword in keywords):
                return TOPICS[topic]["reply"][lang]
        return TEMPLATES[lang][self._calls % len(TEMPLATES[lang])]
