"""Server-side speech synthesis: ``POST /api/v1/tts`` -> audio bytes.

Two voices, one route, 2026-11-14:

* **DeepSeek TTS** is the primary voice when a DeepSeek key is configured. It is
  the same account the conversation uses, it is billed per character, and it
  answers with WAV — so the media type is ``audio/wav`` and the client names its
  temp file from the container (it used to hardcode ``.mp3``).
* **Microsoft edge-tts** stays as the fallback: free, no key, and it is the only
  one of the two that can slow the voice down for an older ear. If DeepSeek
  answers 429/503/504, times out, or hands back a truncated file, the reply is
  spoken by edge-tts instead of failing.

Both adapters expose ``synthesize(text, voice, rate) -> bytes`` and a
``media_type``; the route does not care which one answered. If neither can
speak, the honest 503 is returned (never silence).

Provider choice comes from the environment so a packaged build needs no code
change: ``ANCHOR_TTS_PROVIDER`` = ``deepseek`` (default when a key exists) or
``edge``. ``ANCHOR_TTS_VOICE`` may be ``stella``/``tide`` (DeepSeek) or an
edge-tts voice name.
"""

from __future__ import annotations

import os
from typing import Any, Optional, Protocol

from fastapi import APIRouter, Depends, Response
from pydantic import BaseModel

from ..errors import AppError, provider_unavailable, validation_error
from ..providers.tts import MAX_TEXT_CHARS, EdgeTTS
from ..providers.tts_deepseek import DEFAULT_BASE_URL, DeepSeekTTS
from .deps import current_user

router = APIRouter(tags=["tts"])

#: Header used to tell the client which voice actually spoke. Useful in logs, in
#: the demo, and in tests; it never contains the key.
PROVIDER_HEADER = "X-Anchor-Voice"

_SYNTHESIZER: Optional["SpeechBackend"] = None


class Speech(Protocol):
    media_type: str

    def synthesize(
        self, text: str, voice: Optional[str] = None, rate: Optional[str] = None
    ) -> bytes: ...


class SpeechBackend:
    """The voice the app speaks with: a primary, a fallback, and a name.

    Both attributes are updated on every successful call, so the route reports
    what actually produced the bytes it is returning rather than what was hoped
    for: if DeepSeek failed and edge-tts answered, the media type is mp3 and the
    header says ``edge``.
    """

    def __init__(
        self,
        primary: Speech,
        fallback: Optional[Speech] = None,
        name: str = "deepseek",
    ) -> None:
        self.primary = primary
        self.fallback = fallback
        self.name = name
        self.spoken_with = name
        self.media_type = getattr(primary, "media_type", "audio/mpeg")

    def synthesize(
        self, text: str, voice: Optional[str] = None, rate: Optional[str] = None
    ) -> bytes:
        try:
            audio = self.primary.synthesize(text, voice=voice, rate=rate)
            self.spoken_with = self.name
            self.media_type = getattr(self.primary, "media_type", "audio/mpeg")
            return audio
        except AppError as error:
            # Only an unavailable provider is worth a second attempt; a
            # validation or auth error would fail the same way twice.
            if self.fallback is None or error.code != "provider_unavailable":
                raise
        # The senior hears the robotic-but-present voice instead of nothing, and
        # the log explains why the voice changed for one sentence.
        audio = self.fallback.synthesize(text, voice=voice, rate=rate)
        self.spoken_with = "edge"
        self.media_type = getattr(self.fallback, "media_type", "audio/mpeg")
        return audio


def _env(name: str) -> str:
    return (os.environ.get(name) or "").strip()


def _deepseek_key() -> str:
    # The chat key is the one the packaged build injects; a dedicated TTS key is
    # accepted too for a deployment that wants them separate.
    return _env("ANCHOR_TTS_API_KEY") or _env("ANCHOR_LLM_API_KEY")


def build_backend() -> SpeechBackend:
    """Compose the voice from the environment (no network, no side effects)."""
    preferred = _env("ANCHOR_TTS_PROVIDER").lower()
    key = _deepseek_key()
    edge = EdgeTTS()
    if preferred == "edge" or (preferred != "deepseek" and not key):
        return SpeechBackend(primary=edge, name="edge")
    deepseek = DeepSeekTTS(
        api_key=key,
        base_url=_env("ANCHOR_TTS_BASE_URL") or _env("ANCHOR_LLM_BASE_URL") or DEFAULT_BASE_URL,
        voice=_env("ANCHOR_TTS_VOICE") or "stella",
    )
    return SpeechBackend(primary=deepseek, fallback=edge, name="deepseek")


def get_tts() -> SpeechBackend:
    """One process-wide voice; tests override this FastAPI dependency."""
    global _SYNTHESIZER
    if _SYNTHESIZER is None:
        _SYNTHESIZER = build_backend()
    return _SYNTHESIZER


def reset_synthesizer() -> None:
    """Forget the cached backend (tests, and a settings change at runtime)."""
    global _SYNTHESIZER
    _SYNTHESIZER = None


class TTSIn(BaseModel):
    text: str
    voice: Optional[str] = None
    rate: Optional[str] = None


@router.post("/tts")
def synthesize_speech(
    body: TTSIn,
    user: dict[str, Any] = Depends(current_user),
    tts: SpeechBackend = Depends(get_tts),
) -> Response:
    text = body.text.strip()
    if not text:
        raise validation_error("text must not be blank")
    if len(text) > MAX_TEXT_CHARS:
        raise validation_error(f"text must be at most {MAX_TEXT_CHARS} characters")
    audio = tts.synthesize(text, voice=body.voice, rate=body.rate)
    # getattr keeps the route working for a bare adapter too (the tests inject
    # an EdgeTTS with a fake synth, which has no backend bookkeeping).
    return Response(
        content=audio,
        media_type=getattr(tts, 'media_type', 'audio/mpeg'),
        headers={PROVIDER_HEADER: getattr(tts, 'spoken_with', 'edge')},
    )
