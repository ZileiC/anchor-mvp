"""Transcription-only speech recognition: ``POST /api/v1/transcribe``.

The Play/activity screen records a spoken answer and needs the words without
starting a conversation turn: no session, no LLM call, and nothing written to
the database. The short-lived audio is decoded in memory and handed straight to
the configured ASR adapter (``ctx.providers["asr"]``) — the same adapter the
conversation pipeline uses — so a quiz answer is never sent to the chat model.

Failures stay in the shared error envelope: malformed, empty or oversized audio
is a 422 ``validation_error``; an adapter that cannot serve the request (not
configured, unreachable, nothing heard) raises its ``AppError`` and the installed
handler turns it into a 503 ``provider_unavailable`` with recovery options. The
route never catches provider errors and never logs audio or transcript content.
"""

from __future__ import annotations

import base64
import binascii
from typing import Any, Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from ..errors import provider_unavailable, validation_error
from ..providers.config import describe_providers, load_provider_settings
from .deps import get_context, require_senior

router = APIRouter(tags=["asr"])

MAX_AUDIO_BYTES = 8 * 1024 * 1024
DEFAULT_AUDIO_MIME = "audio/wav"

# Adapter class -> the name the client sees. The live adapter wins over the
# resolved configuration because it is what actually served this request.
_PROVIDER_NAMES = {
    "HttpASR": "http",
    "WindowsSapiASR": "windows-sapi",
    "FakeASR": "fake",
    "UnavailableASR": "none",
}


class TranscribeIn(BaseModel):
    audio_b64: Optional[str] = None
    audio_mime: Optional[str] = None


def _decode_audio(value: Any) -> bytes:
    """Decode and bound the payload; bad input becomes a clear 422."""
    if not isinstance(value, str) or not value:
        raise validation_error("audio_b64 must be a non-empty base64 string")
    try:
        audio = base64.b64decode(value, validate=True)
    except (binascii.Error, ValueError) as exc:
        raise validation_error("audio_b64 is not valid base64") from exc
    if not isinstance(audio, (bytes, bytearray)) or not audio:
        # b64decode always returns bytes, but the type check keeps the contract
        # honest if the decoder is ever swapped out.
        raise validation_error("audio_b64 decodes to an empty payload")
    if len(audio) > MAX_AUDIO_BYTES:
        raise validation_error("audio payload is too large (max 8 MB)")
    return bytes(audio)


def _provider_name(ctx, adapter: Any) -> str:
    """Best effort: name the ASR backend, falling back to the resolved mode."""
    for cls in type(adapter).__mro__:
        name = _PROVIDER_NAMES.get(cls.__name__)
        if name is not None:
            return name
    try:
        stored = load_provider_settings(ctx.db)
        return str(describe_providers(ctx.settings, stored)["asr"]["engine"])
    except Exception:  # noqa: BLE001 - a label must never fail the transcription
        return type(adapter).__name__


@router.post("/transcribe")
def transcribe(
    body: TranscribeIn = TranscribeIn(),
    user: dict[str, Any] = Depends(require_senior),
    ctx=Depends(get_context),
) -> dict[str, Any]:
    audio = _decode_audio(body.audio_b64)
    mime = (body.audio_mime or "").strip() or DEFAULT_AUDIO_MIME
    adapter = ctx.providers.get("asr")
    if adapter is None:
        raise provider_unavailable(
            "Speech recognition is not configured.",
            recovery=["type_instead", "configure"],
            provider="asr",
        )
    text = adapter.transcribe(audio, mime)
    return {"text": text, "provider": _provider_name(ctx, adapter)}
