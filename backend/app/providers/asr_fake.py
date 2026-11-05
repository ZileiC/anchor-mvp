"""Deterministic speech-to-text fake for tests and offline demos."""

from __future__ import annotations


class FakeASR:
    def __init__(self, transcript: str = "我今天吃过饭了") -> None:
        self.transcript = transcript
        self.calls: list[tuple[int, str]] = []

    def set_transcript(self, transcript: str) -> None:
        self.transcript = transcript

    def transcribe(self, audio: bytes, mime: str = "audio/wav") -> str:
        self.calls.append((len(audio), mime))
        return self.transcript


class FailingASR:
    """Always raises provider_unavailable, used by recovery tests."""

    def transcribe(self, audio: bytes, mime: str = "audio/wav") -> str:
        from ..errors import provider_unavailable

        raise provider_unavailable("Speech recognition is not reachable right now.")
