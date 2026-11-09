"""Tolerant endpoint URLs for OpenAI-compatible providers.

A user typo here produces a confusing 404 from the provider, so accept every
shape an operator or the Settings screen may paste:

* ``https://api.deepseek.com``                     -> ``https://api.deepseek.com/chat/completions``
* ``https://api.deepseek.com/v1``                  -> ``https://api.deepseek.com/v1/chat/completions``
* ``https://api.deepseek.com/v1/chat/completions`` -> unchanged (never double-append)
* ``https://api.deepseek.com/v1/``                 -> ``https://api.deepseek.com/v1/chat/completions``
"""

from __future__ import annotations


def _endpoint(base_url: str, suffix: str) -> str:
    base = (base_url or "").strip().rstrip("/")
    if not base:
        raise ValueError("provider base URL is empty")
    if base.endswith(suffix):
        return base
    return f"{base}{suffix}"


def chat_completions_url(base_url: str) -> str:
    return _endpoint(base_url, "/chat/completions")


def audio_transcriptions_url(base_url: str) -> str:
    return _endpoint(base_url, "/audio/transcriptions")
