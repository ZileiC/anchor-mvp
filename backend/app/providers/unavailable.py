"""Honest "not configured" adapters.

The demo must never invent conversation or a transcript. When no provider is
configured these adapters refuse with ``provider_unavailable`` (HTTP 503) and
tell the caller what to do instead: type, or fill in the Settings screen.
"""

from __future__ import annotations

from ..errors import provider_unavailable

RECOVERY = ["type_instead", "configure"]

ASR_NOT_CONFIGURED = "语音识别还没有接入，请打字，或到设置里填写 ASR 接口"
ASR_INCOMPLETE = "语音识别接口还没填完整（缺少 API key），请到设置里补上"
ASR_BAD_AUDIO = "目前只能识别 WAV 格式的语音，请换一种输入方式，或直接打字"

LLM_NOT_CONFIGURED = "对话模型还没有接入，请打字继续，或到设置里填写 LLM 接口"
LLM_INCOMPLETE = "对话模型接口还没填完整（缺少 API key），请到设置里补上"


class UnavailableASR:
    """Refuses to transcribe; never returns a canned transcript."""

    def __init__(self, message: str = ASR_NOT_CONFIGURED) -> None:
        self.message = message

    def transcribe(self, audio: bytes, mime: str = "audio/wav") -> str:
        raise provider_unavailable(self.message, recovery=list(RECOVERY), provider="asr")


class UnavailableLLM:
    """Refuses to answer; never returns a canned reply."""

    def __init__(self, message: str = LLM_NOT_CONFIGURED) -> None:
        self.message = message

    def reply(
        self,
        system: str,
        turns: list[dict[str, str]],
        max_words: int = 30,
    ) -> str:
        raise provider_unavailable(self.message, recovery=list(RECOVERY), provider="llm")
