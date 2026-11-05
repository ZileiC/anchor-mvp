"""Provider adapter boundaries (SPEC §2: swap without business-logic change)."""

from __future__ import annotations

from typing import Protocol


class ASRAdapter(Protocol):
    """Speech-to-text."""

    def transcribe(self, audio: bytes, mime: str = "audio/wav") -> str: ...


class LLMAdapter(Protocol):
    """Short, safe conversational replies."""

    def reply(self, system: str, turns: list[dict[str, str]], max_words: int) -> str: ...


class NotifierProtocol(Protocol):
    def notify(self, user_id: int, kind: str, message_key: str) -> int: ...
