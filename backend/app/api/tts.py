"""Server-side neural speech synthesis: ``POST /api/v1/tts`` -> ``audio/mpeg``.

The Talk screen sends the sentence it wants spoken and plays the returned MP3
locally. Synthesis is network-bound and takes seconds, so the route is a plain
``def`` (FastAPI runs it in its threadpool); the adapter enforces a 15 s budget.

The synthesizer arrives through a dependency so tests can inject a fake one and
never touch Microsoft's service.
"""

from __future__ import annotations

from typing import Any, Optional

from fastapi import APIRouter, Depends, Response
from pydantic import BaseModel

from ..errors import validation_error
from ..providers.tts import MAX_TEXT_CHARS, EdgeTTS
from .deps import current_user

router = APIRouter(tags=["tts"])

AUDIO_MIME = "audio/mpeg"

_SYNTHESIZER: Optional[EdgeTTS] = None


def get_tts() -> EdgeTTS:
    """One process-wide adapter; tests override this FastAPI dependency."""
    global _SYNTHESIZER
    if _SYNTHESIZER is None:
        _SYNTHESIZER = EdgeTTS()
    return _SYNTHESIZER


class TTSIn(BaseModel):
    text: str
    voice: Optional[str] = None
    rate: Optional[str] = None


@router.post("/tts")
def synthesize_speech(
    body: TTSIn,
    user: dict[str, Any] = Depends(current_user),
    tts: EdgeTTS = Depends(get_tts),
) -> Response:
    text = body.text.strip()
    if not text:
        raise validation_error("text must not be blank")
    if len(text) > MAX_TEXT_CHARS:
        raise validation_error(f"text must be at most {MAX_TEXT_CHARS} characters")
    audio = tts.synthesize(text, voice=body.voice, rate=body.rate)
    return Response(content=audio, media_type=AUDIO_MIME)
