"""OpenAI-compatible endpoint joining accepts every base-URL shape once."""

from __future__ import annotations

import httpx
import pytest

from app.providers.asr_http import HttpASR
from app.providers.llm_http import HttpLLM
from app.providers.urls import audio_transcriptions_url, chat_completions_url


@pytest.mark.parametrize(
    "base,expected",
    [
        ("https://api.deepseek.com", "https://api.deepseek.com/chat/completions"),
        ("https://api.deepseek.com/v1", "https://api.deepseek.com/v1/chat/completions"),
        ("https://api.deepseek.com/", "https://api.deepseek.com/chat/completions"),
        ("https://api.deepseek.com/v1/", "https://api.deepseek.com/v1/chat/completions"),
        (
            "https://api.deepseek.com/v1/chat/completions",
            "https://api.deepseek.com/v1/chat/completions",
        ),
        (
            "https://api.deepseek.com/chat/completions/",
            "https://api.deepseek.com/chat/completions",
        ),
    ],
)
def test_chat_completions_url_never_double_appends(base, expected):
    assert chat_completions_url(base) == expected
    assert HttpLLM(base).url == expected


@pytest.mark.parametrize(
    "base,expected",
    [
        ("https://asr.example/v1", "https://asr.example/v1/audio/transcriptions"),
        ("https://asr.example", "https://asr.example/audio/transcriptions"),
        (
            "https://asr.example/v1/audio/transcriptions",
            "https://asr.example/v1/audio/transcriptions",
        ),
    ],
)
def test_audio_transcriptions_url_never_double_appends(base, expected):
    assert audio_transcriptions_url(base) == expected
    assert HttpASR(base).url == expected


def test_http_llm_calls_the_joined_url_once():
    seen: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(str(request.url))
        return httpx.Response(200, json={"choices": [{"message": {"content": "hi"}}]})

    HttpLLM("https://api.deepseek.com/v1", transport=httpx.MockTransport(handler)).reply(
        "sys", [{"role": "user", "content": "hi"}]
    )
    assert seen == ["https://api.deepseek.com/v1/chat/completions"]
