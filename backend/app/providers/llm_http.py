"""OpenAI-compatible chat adapter (``/chat/completions``)."""

from __future__ import annotations

from typing import Any, Optional

import httpx

from ..errors import provider_unavailable


class HttpLLM:
    def __init__(
        self,
        base_url: str,
        api_key: Optional[str] = None,
        model: Optional[str] = None,
        timeout: float = 20.0,
        max_tokens: int = 220,
        transport: Optional[httpx.BaseTransport] = None,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.api_key = api_key
        self.model = model or "gpt-4o-mini"
        self.timeout = timeout
        self.max_tokens = max_tokens
        self.transport = transport

    @property
    def url(self) -> str:
        return f"{self.base_url}/chat/completions"

    def _headers(self) -> dict[str, str]:
        headers = {"Content-Type": "application/json"}
        if self.api_key:
            headers["Authorization"] = f"Bearer {self.api_key}"
        return headers

    def reply(self, system: str, turns: list[dict[str, str]], max_words: int = 30) -> str:
        messages: list[dict[str, str]] = [{"role": "system", "content": system}]
        messages.extend(turns)
        payload = {
            "model": self.model,
            "messages": messages,
            "max_tokens": self.max_tokens,
            "temperature": 0.4,
        }
        try:
            with httpx.Client(timeout=self.timeout, transport=self.transport) as client:
                response = client.post(self.url, headers=self._headers(), json=payload)
        except httpx.HTTPError as exc:
            raise provider_unavailable(
                "The conversation service is not reachable right now.",
                recovery=["retry", "type_instead"],
            ) from exc
        if response.status_code >= 400:
            raise provider_unavailable(
                "The conversation service is not reachable right now.",
                recovery=["retry", "type_instead"],
            )
        try:
            data: Any = response.json()
            text = data["choices"][0]["message"]["content"]
        except (ValueError, KeyError, IndexError, TypeError) as exc:
            raise provider_unavailable("The conversation service returned an unreadable answer.") from exc
        if not isinstance(text, str) or not text.strip():
            raise provider_unavailable("The conversation service returned an empty answer.")
        return text.strip()
