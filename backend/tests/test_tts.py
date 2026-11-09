"""Server-side TTS: ``POST /api/v1/tts`` and the edge-tts adapter.

The HTTP tests go through the real app with an injected fake synthesizer, so the
suite never opens a socket. The default ``edge_tts`` path is covered separately
by swapping the ``edge_tts`` module in ``sys.modules`` — same code, no network.
"""

from __future__ import annotations

import asyncio
import sys
import types
from typing import Any, Optional

import pytest

from app.api import tts as tts_api
from app.errors import AppError
from app.providers.tts import (
    DEFAULT_RATE,
    DEFAULT_VOICE,
    MAX_TEXT_CHARS,
    EdgeTTS,
)
from tests import helpers

AUDIO = b"ID3\x04\x00\x00\x00\x00\x00\x00fake-mp3-payload"


class FakeSynth:
    """Records every call and returns fixed MP3 bytes (or raises ``error``)."""

    def __init__(self, audio: bytes = AUDIO, error: Optional[Exception] = None) -> None:
        self.audio = audio
        self.error = error
        self.calls: list[tuple[str, str, str]] = []

    def __call__(self, text: str, voice: str, rate: str) -> bytes:
        self.calls.append((text, voice, rate))
        if self.error is not None:
            raise self.error
        return self.audio


@pytest.fixture
def fake_synth() -> FakeSynth:
    return FakeSynth()


@pytest.fixture
def fake_tts(app, fake_synth: FakeSynth) -> FakeSynth:
    """Point the route's dependency at the fake; no network is reachable."""
    app.dependency_overrides[tts_api.get_tts] = lambda: EdgeTTS(synth=fake_synth)
    yield fake_synth
    app.dependency_overrides.pop(tts_api.get_tts, None)


def post_tts(client, token: str, payload: dict[str, Any]):
    return client.post("/api/v1/tts", json=payload, headers=helpers.headers(token))


# -- the HTTP contract ------------------------------------------------------
def test_tts_returns_raw_mp3_with_audio_content_type(client, senior_token, fake_tts):
    response = post_tts(client, senior_token, {"text": "今天天气不错，我们出去走走吧。"})

    assert response.status_code == 200
    assert response.headers["content-type"] == "audio/mpeg"
    assert response.content == AUDIO
    assert len(response.content) == len(AUDIO)


def test_tts_strips_text_and_uses_default_voice_and_rate(client, senior_token, fake_tts):
    response = post_tts(client, senior_token, {"text": "  你好呀  "})

    assert response.status_code == 200
    assert fake_tts.calls == [("你好呀", DEFAULT_VOICE, DEFAULT_RATE)]
    assert DEFAULT_VOICE == "zh-CN-XiaoxiaoNeural"
    assert DEFAULT_RATE == "-12%"


def test_tts_passes_explicit_voice_and_rate_through(client, senior_token, fake_tts):
    response = post_tts(
        client,
        senior_token,
        {"text": "你好", "voice": "zh-CN-YunxiNeural", "rate": "+0%"},
    )

    assert response.status_code == 200
    assert fake_tts.calls == [("你好", "zh-CN-YunxiNeural", "+0%")]


def test_tts_blank_voice_and_rate_fall_back_to_defaults(client, senior_token, fake_tts):
    response = post_tts(client, senior_token, {"text": "你好", "voice": "   ", "rate": ""})

    assert response.status_code == 200
    assert fake_tts.calls == [("你好", DEFAULT_VOICE, DEFAULT_RATE)]


@pytest.mark.parametrize("text", ["", "   ", "\n\t "])
def test_tts_blank_text_is_422(client, senior_token, fake_tts, text):
    response = post_tts(client, senior_token, {"text": text})

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"
    assert fake_tts.calls == []


def test_tts_missing_text_is_422(client, senior_token, fake_tts):
    response = post_tts(client, senior_token, {})

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"
    assert fake_tts.calls == []


def test_tts_text_over_2000_chars_is_422(client, senior_token, fake_tts):
    response = post_tts(client, senior_token, {"text": "啊" * (MAX_TEXT_CHARS + 1)})

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"
    assert fake_tts.calls == []


def test_tts_text_at_the_2000_char_limit_is_accepted(client, senior_token, fake_tts):
    response = post_tts(client, senior_token, {"text": "啊" * MAX_TEXT_CHARS})

    assert response.status_code == 200
    assert fake_tts.calls[0][0] == "啊" * MAX_TEXT_CHARS


def test_tts_provider_failure_is_503_with_the_error_envelope(client, senior_token, fake_tts):
    fake_tts.error = OSError("network is down")

    response = post_tts(client, senior_token, {"text": "你好"})

    assert response.status_code == 503
    assert response.headers["content-type"].startswith("application/json")
    error = response.json()["error"]
    assert error["code"] == "provider_unavailable"
    assert error["provider"] == "tts"
    assert error["recovery"] == ["retry", "type_instead"]


def test_tts_without_a_token_is_401(client, fake_tts):
    response = client.post("/api/v1/tts", json={"text": "你好"})

    assert response.status_code == 401
    assert response.json()["error"]["code"] == "unauthorized"
    assert fake_tts.calls == []


# -- the real adapter, with the edge_tts module faked -----------------------
def _install_fake_edge_tts(monkeypatch, communicate_cls: type) -> None:
    module = types.ModuleType("edge_tts")
    module.Communicate = communicate_cls  # type: ignore[attr-defined]
    monkeypatch.setitem(sys.modules, "edge_tts", module)


def test_edge_tts_collects_only_audio_chunks(monkeypatch):
    calls: list[tuple[str, str, str]] = []

    class FakeCommunicate:
        def __init__(self, text: str, voice: str, *, rate: str = "+0%") -> None:
            calls.append((text, voice, rate))

        async def stream(self):
            yield {"type": "audio", "data": b"abc"}
            yield {"type": "SentenceBoundary", "data": {"offset": 0}}
            yield {"type": "audio", "data": b"def"}

    _install_fake_edge_tts(monkeypatch, FakeCommunicate)

    audio = EdgeTTS().synthesize("你好", voice="zh-CN-YunxiNeural", rate="+0%")

    assert audio == b"abcdef"
    assert calls == [("你好", "zh-CN-YunxiNeural", "+0%")]


def test_edge_tts_timeout_is_provider_unavailable(monkeypatch):
    class SlowCommunicate:
        def __init__(self, *_args, **_kwargs) -> None:
            pass

        async def stream(self):
            await asyncio.sleep(5)
            yield {"type": "audio", "data": b"too late"}

    _install_fake_edge_tts(monkeypatch, SlowCommunicate)

    with pytest.raises(AppError) as excinfo:
        EdgeTTS(timeout=0.05).synthesize("你好")

    assert excinfo.value.code == "provider_unavailable"
    assert excinfo.value.status == 503
    assert "timed out" in excinfo.value.message.lower()


def test_edge_tts_empty_stream_is_provider_unavailable(monkeypatch):
    class SilentCommunicate:
        def __init__(self, *_args, **_kwargs) -> None:
            pass

        async def stream(self):
            if False:  # pragma: no cover - makes this an async generator
                yield {"type": "audio", "data": b""}

    _install_fake_edge_tts(monkeypatch, SilentCommunicate)

    with pytest.raises(AppError) as excinfo:
        EdgeTTS().synthesize("你好")

    assert excinfo.value.code == "provider_unavailable"
    assert "no audio" in excinfo.value.message.lower()


def test_edge_tts_missing_package_degrades_to_provider_unavailable(monkeypatch):
    """A frozen bundle without edge_tts must 503 this endpoint, not crash boot."""
    monkeypatch.setitem(sys.modules, "edge_tts", None)

    with pytest.raises(AppError) as excinfo:
        EdgeTTS().synthesize("你好")

    assert excinfo.value.code == "provider_unavailable"
    assert excinfo.value.status == 503
