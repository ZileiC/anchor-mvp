"""Real neural text-to-speech through Microsoft Edge's online TTS service.

The app speaks the assistant's reply to an older adult; the machine's SAPI voice
sounds robotic, so this adapter asks ``edge-tts`` for a neural MP3 and hands the
raw bytes back to the client, which owns playback.

Nothing is fabricated. A network failure, the 15 s budget expiring, an empty
stream or a missing ``edge-tts`` install all raise ``provider_unavailable``
(HTTP 503, recovery hints) instead of returning silence or an empty 200.

``edge-tts`` is imported lazily inside the synthesis call: if the frozen bundle
ever ships without it (or with a broken CA store) only this endpoint degrades to
its honest 503, instead of the whole backend failing to start.

The synthesis callable is injectable (``synth=``) so unit tests never open a
WebSocket to Microsoft.
"""

from __future__ import annotations

import asyncio
from typing import Callable, List, Optional

from ..errors import AppError, provider_unavailable

DEFAULT_VOICE = "zh-CN-XiaoxiaoNeural"
# Slower than the neural voice's natural pace: easier to follow for older ears.
DEFAULT_RATE = "-12%"
MAX_TEXT_CHARS = 2000
TIMEOUT_SECONDS = 15.0

PROVIDER = "tts"
RECOVERY = ["retry", "type_instead"]

# (text, voice, rate) -> mp3 bytes
Synth = Callable[[str, str, str], bytes]


def _edge_synthesize(
    text: str,
    voice: str,
    rate: str,
    *,
    timeout: float = TIMEOUT_SECONDS,
) -> bytes:
    """Collect the MP3 chunks that Edge's neural voice streams back.

    Runs in a private event loop (FastAPI serves the sync endpoint from its
    threadpool), and ``asyncio.wait_for`` enforces the budget *and* cancels the
    WebSocket when it expires, so a hung connection cannot pin a worker.
    """

    async def collect() -> bytes:
        import edge_tts

        communicate = edge_tts.Communicate(text, voice, rate=rate)
        chunks: List[bytes] = []
        async for message in communicate.stream():
            if message.get("type") != "audio":
                continue
            data = message.get("data")
            if data:
                chunks.append(data)
        return b"".join(chunks)

    try:
        audio = asyncio.run(asyncio.wait_for(collect(), timeout=timeout))
    except asyncio.TimeoutError as exc:
        raise provider_unavailable(
            "Speech synthesis timed out.",
            recovery=list(RECOVERY),
            provider=PROVIDER,
        ) from exc
    except AppError:
        raise
    except Exception as exc:  # noqa: BLE001 - a provider failure is never a 500
        raise provider_unavailable(
            "Speech synthesis is not reachable right now.",
            recovery=list(RECOVERY),
            provider=PROVIDER,
        ) from exc
    if not audio:
        raise provider_unavailable(
            "Speech synthesis returned no audio.",
            recovery=list(RECOVERY),
            provider=PROVIDER,
        )
    return audio


class EdgeTTS:
    """Neural TTS adapter with an injectable synthesis seam for tests."""

    def __init__(
        self,
        synth: Optional[Synth] = None,
        *,
        voice: str = DEFAULT_VOICE,
        rate: str = DEFAULT_RATE,
        timeout: float = TIMEOUT_SECONDS,
    ) -> None:
        self.voice = voice
        self.rate = rate
        self.timeout = timeout
        self._synth: Synth = synth or (
            lambda text, selected_voice, selected_rate: _edge_synthesize(
                text, selected_voice, selected_rate, timeout=timeout
            )
        )

    def synthesize(
        self,
        text: str,
        voice: Optional[str] = None,
        rate: Optional[str] = None,
    ) -> bytes:
        """Return MP3 bytes for ``text``; blank overrides fall back to defaults."""
        chosen_voice = (voice or "").strip() or self.voice
        chosen_rate = (rate or "").strip() or self.rate
        try:
            audio = self._synth(text, chosen_voice, chosen_rate)
        except AppError:
            raise
        except Exception as exc:  # noqa: BLE001 - a provider failure is never a 500
            raise provider_unavailable(
                "Speech synthesis is not reachable right now.",
                recovery=list(RECOVERY),
                provider=PROVIDER,
            ) from exc
        if not isinstance(audio, (bytes, bytearray)) or not audio:
            raise provider_unavailable(
                "Speech synthesis returned no audio.",
                recovery=list(RECOVERY),
                provider=PROVIDER,
            )
        return bytes(audio)
