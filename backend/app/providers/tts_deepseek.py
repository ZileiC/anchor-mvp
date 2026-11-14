"""DeepSeek's own text-to-speech, 2026-11-14.

DeepSeek opened a TTS tool API on 2026-11-13 (api-docs.deepseek.com/guides/tts):
same host and key as the chat model, which is why this is worth using — the
appliance already talks to that endpoint for chat, so speech needs no second
vendor, no second key and no second bill.

Why it replaces Microsoft's edge-tts as the primary voice:

* it is the same account as the conversation, so a demo has one credential;
* it answers **as it synthesizes** (the response body streams) and it is billed
  per character (1.5 元 / 10k characters, 50% off), not per request;
* it returns WAV or 24 kHz PCM, both playable by the two platforms we ship.

What it cannot do, and this module refuses to pretend otherwise:

* **no speed control** ("Speed control ... not supported" in the docs). Our
  ``rate`` argument exists for interface compatibility and is ignored; the
  ``慢一点`` preference therefore only affects the edge-tts fallback, which is
  documented in HANDOVER.
* no mp3. The bytes are WAV, so the client must name its temp file accordingly
  (``mobile/lib/services/speech_audio_format.dart`` sniffs the container).

Failure modes are reported honestly, never as silence: an unreachable host, an
HTTP error (400 content review, 429 too many concurrent requests, 503 busy,
504 timeout), a body that is not RIFF/WAVE, or a body that stops early (the docs
warn that a failed synthesis truncates the stream) all become
``provider_unavailable`` so the caller can fall back to the other voice.
"""

from __future__ import annotations

from typing import Any, Optional

import httpx

from ..errors import provider_unavailable

#: Where the tool API lives. The chat model uses the same origin.
DEFAULT_BASE_URL = "https://api.deepseek.com"
TTS_PATH = "/v1/tools/tts"

#: The two voices the API currently exposes.
VOICE_FEMALE = "stella"
VOICE_MALE = "tide"
DEFAULT_VOICE = VOICE_FEMALE
VOICES = (VOICE_FEMALE, VOICE_MALE)

#: Our public text cap (same as the edge adapter's). The API's own limit is
#: 10,000 *billed* characters and a 64 KiB body; we stay well below both.
MAX_TEXT_CHARS = 2000

#: Synthesis is network-bound; the route runs in FastAPI's threadpool.
TIMEOUT_SECONDS = 15.0

PROVIDER = "tts"
RECOVERY = ["retry", "type_instead"]

WAV_MAGIC = (b"RIFF", b"WAVE")


def wav_from_bytes(audio: bytes) -> bool:
    """True when ``audio`` looks like a complete little RIFF/WAVE file.

    The docs say a failed synthesis truncates the stream, so the header check is
    not paranoia: half a WAV opens as silence on Windows, which is exactly the
    failure this app must never present.
    """
    if len(audio) < 44:  # smallest sane WAV header
        return False
    if not audio.startswith(WAV_MAGIC[0]):
        return False
    if audio[8:12] != WAV_MAGIC[1]:
        return False
    return True


def normalize_wav(audio: bytes) -> bytes:
    """Write the real sizes into a streamed WAV header.

    DeepSeek streams the audio, so the header it sends carries the placeholders
    ``0xFFFFFFFF`` for both the RIFF size and the data-chunk size (measured on
    2026-11-14: 4294967295 in both fields). Python's own ``wave`` module refuses
    such a file outright, and players disagree about it — Windows plays until EOF,
    Android's ExoPlayer may report a wrong duration. We hold the complete body, so
    the honest header is one we can write ourselves.

    Leaves an already-correct file untouched (the bytes compare equal for real
    sizes), and does nothing to a body without the two expected chunks.
    """
    if not wav_from_bytes(audio):
        return audio
    buffer = bytearray(audio)
    data_at = buffer.find(b"data", 12)
    if data_at < 0:
        return audio
    riff_size = len(buffer) - 8
    data_size = len(buffer) - (data_at + 8)
    buffer[4:8] = riff_size.to_bytes(4, "little", signed=False)
    buffer[data_at + 4 : data_at + 8] = data_size.to_bytes(4, "little", signed=False)
    return bytes(buffer)


def resolve_voice(voice: Optional[str]) -> str:
    """Map the names our settings already use onto the two real voices.

    The appliance's stored default is `zh-CN-XiaoxiaoNeural` (edge's female
    Chinese voice) and the older ``slow`` path passes the same string, so an
    exact-match-only mapping would silently send an invalid voice id.
    """
    chosen = (voice or "").strip().lower()
    if not chosen:
        return DEFAULT_VOICE
    if chosen in VOICES:
        return chosen
    if "tide" in chosen or "yunxi" in chosen or "yunyang" in chosen or "male" in chosen:
        return VOICE_MALE
    # Anything else (xiaoxiao, xiaoyi, the old default, an unknown id) is the
    # product's female voice: better a wrong-but-valid voice than a 400.
    return VOICE_FEMALE


class DeepSeekTTS:
    """Text → WAV bytes through DeepSeek's tool API."""

    media_type = "audio/wav"

    def __init__(
        self,
        api_key: str,
        base_url: str = DEFAULT_BASE_URL,
        voice: str = DEFAULT_VOICE,
        timeout: float = TIMEOUT_SECONDS,
        transport: Optional[httpx.BaseTransport] = None,
    ) -> None:
        self.api_key = api_key
        self.base_url = base_url.rstrip("/")
        self.voice = resolve_voice(voice)
        self.timeout = timeout
        self.transport = transport

    @property
    def url(self) -> str:
        return f"{self.base_url}{TTS_PATH}"

    def _headers(self) -> dict[str, str]:
        return {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }

    def synthesize(
        self,
        text: str,
        voice: Optional[str] = None,
        rate: Optional[str] = None,
    ) -> bytes:
        """Return WAV bytes for ``text``.

        ``rate`` is accepted and ignored on purpose: this provider has no speed
        control, and pretending to slow the voice down would be a lie the user
        hears. The caller logs which provider actually spoke.
        """
        payload = {
            "text": text,
            "voice_id": resolve_voice(voice or self.voice),
            "format": "wav",
            "filter_markdown": True,
        }
        try:
            with httpx.Client(timeout=self.timeout, transport=self.transport) as client:
                response = client.post(self.url, headers=self._headers(), json=payload)
        except httpx.TimeoutException as exc:
            raise provider_unavailable(
                "Speech synthesis timed out.",
                recovery=list(RECOVERY),
                provider=PROVIDER,
            ) from exc
        except httpx.HTTPError as exc:
            raise provider_unavailable(
                "Speech synthesis is not reachable right now.",
                recovery=list(RECOVERY),
                provider=PROVIDER,
            ) from exc

        if response.status_code >= 400:
            raise provider_unavailable(
                f"Speech synthesis answered with an error (HTTP {response.status_code}).",
                recovery=list(RECOVERY),
                provider=PROVIDER,
            )

        audio = response.content
        if not audio:
            raise provider_unavailable(
                "Speech synthesis returned no audio.",
                recovery=list(RECOVERY),
                provider=PROVIDER,
            )
        if not wav_from_bytes(audio):
            # Either the content filter cut the stream or the response stopped
            # early; both are failures, never "quiet audio".
            raise provider_unavailable(
                "Speech synthesis returned an incomplete audio file.",
                recovery=list(RECOVERY),
                provider=PROVIDER,
            )
        return normalize_wav(audio)
