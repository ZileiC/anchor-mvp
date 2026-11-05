"""OpenAI-compatible speech-to-text adapter (``/audio/transcriptions``)."""

from __future__ import annotations

from typing import Any, Optional

import httpx

from ..errors import provider_unavailable


class HttpASR:
    def __init__(
        self,
        base_url: str,
        api_key: Optional[str] = None,
        model: Optional[str] = None,
        timeout: float = 20.0,
        transport: Optional[httpx.BaseTransport] = None,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.api_key = api_key
        self.model = model or "whisper-1"
        self.timeout = timeout
        self.transport = transport

    @property
    def url(self) -> str:
        return f"{self.base_url}/audio/transcriptions"

    def _headers(self) -> dict[str, str]:
        return {"Authorization": f"Bearer {self.api_key}"} if self.api_key else {}

    def transcribe(self, audio: bytes, mime: str = "audio/wav") -> str:
        files = {"file": ("audio.wav", audio, mime or "audio/wav")}
        data = {"model": self.model}
        try:
            with httpx.Client(timeout=self.timeout, transport=self.transport) as client:
                response = client.post(self.url, headers=self._headers(), files=files, data=data)
        except httpx.HTTPError as exc:
            raise provider_unavailable(
                "Speech recognition is not reachable right now.",
                recovery=["retry", "type_instead"],
            ) from exc
        if response.status_code >= 400:
            raise provider_unavailable(
                "Speech recognition is not reachable right now.",
                recovery=["retry", "type_instead"],
            )
        try:
            payload: Any = response.json()
        except ValueError as exc:
            raise provider_unavailable("Speech recognition returned an unreadable answer.") from exc
        text = payload.get("text") if isinstance(payload, dict) else None
        if not isinstance(text, str) or not text.strip():
            raise provider_unavailable(
                "Speech recognition did not hear anything.",
                recovery=["retry", "type_instead"],
            )
        return text.strip()
