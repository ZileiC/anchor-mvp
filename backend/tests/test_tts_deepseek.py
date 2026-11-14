"""DeepSeek's TTS as the primary voice, edge-tts as the fallback (2026-11-14).

Everything here runs against an injected ``httpx.MockTransport`` or a fake
synth: no test opens a socket to DeepSeek or to Microsoft.

The behaviour that matters, and is therefore pinned:

* a valid WAV comes back untouched, with ``audio/wav`` and the voice named in a
  header (the client needs the container to name its temp file);
* every failure mode (HTTP error, timeout, empty body, truncated WAV) becomes the
  honest 503 — except that a configured fallback speaks instead;
* ``rate`` is accepted and ignored by DeepSeek (it has no speed control) and is
  still forwarded to edge-tts, which does;
* the provider is chosen from the environment, so a packaged build needs no code
  change, and a missing key simply means "edge".
"""

from __future__ import annotations

import httpx
import pytest

import app.api.tts as tts_api
from app.providers.tts_deepseek import (
    DeepSeekTTS,
    normalize_wav,
    resolve_voice,
    wav_from_bytes,
)

API_KEY = "sk-test-deepseek-1234"

# A minimal but structurally valid WAV: RIFF/WAVE header, 44 bytes of nothing.
WAV = (
    b"RIFF"
    + (36).to_bytes(4, "little")
    + b"WAVE"
    + b"fmt "
    + (16).to_bytes(4, "little")
    + (1).to_bytes(2, "little")
    + (1).to_bytes(2, "little")
    + (24000).to_bytes(4, "little")
    + (48000).to_bytes(4, "little")
    + (2).to_bytes(2, "little")
    + (16).to_bytes(2, "little")
    + b"data"
    + (0).to_bytes(4, "little")
)
TRUNCATED_WAV = WAV[:20]


def _client(handler) -> httpx.MockTransport:
    return httpx.MockTransport(handler)


def _adapter(handler, **kwargs) -> DeepSeekTTS:
    return DeepSeekTTS(api_key=API_KEY, transport=_client(handler), **kwargs)


# -- the WAV contract ------------------------------------------------------
def test_a_wav_body_is_returned_untouched():
    seen: list[dict] = []

    def handler(request: httpx.Request) -> httpx.Response:
        import json

        seen.append(json.loads(request.content))
        assert request.headers["authorization"] == f"Bearer {API_KEY}"
        assert str(request.url) == "https://api.deepseek.com/v1/tools/tts"
        return httpx.Response(200, content=WAV, headers={"content-type": "audio/wav"})

    audio = _adapter(handler).synthesize("奶奶您好", voice="zh-CN-XiaoxiaoNeural")

    # The body comes back byte-identical when its header already carries real sizes.
    assert normalize_wav(audio) == audio
    assert seen[0]["text"] == "奶奶您好"
    assert seen[0]["format"] == "wav"
    assert seen[0]["voice_id"] == "stella"
    assert seen[0]["filter_markdown"] is True


def test_the_two_real_voices_are_the_only_ones_sent():
    bodies: list[dict] = []

    def handler(request: httpx.Request) -> httpx.Response:
        import json

        bodies.append(json.loads(request.content))
        return httpx.Response(200, content=WAV)

    adapter = _adapter(handler)
    adapter.synthesize("一", voice="tide")
    adapter.synthesize("二", voice="zh-CN-YunxiNeural")
    adapter.synthesize("三", voice="something-unknown")

    assert [body["voice_id"] for body in bodies] == ["tide", "tide", "stella"]


def test_the_request_never_asks_for_more_than_the_api_accepts():
    import json

    seen: list[dict] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(json.loads(request.content))
        return httpx.Response(200, content=WAV)

    _adapter(handler).synthesize("x" * tts_api.MAX_TEXT_CHARS)
    body = seen[0]
    assert len(body["text"]) == tts_api.MAX_TEXT_CHARS
    assert len(json.dumps(body).encode()) < 64 * 1024


# -- failure modes are honest ---------------------------------------------
@pytest.mark.parametrize("status", [400, 429, 500, 503, 504])
def test_http_errors_become_provider_unavailable(status):
    from app.errors import AppError

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(status, json={"error": "nope"})

    with pytest.raises(AppError) as caught:
        _adapter(handler).synthesize("你好")
    assert caught.value.code == "provider_unavailable"


def test_a_timeout_becomes_provider_unavailable():
    from app.errors import AppError

    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ReadTimeout("too slow", request=request)

    with pytest.raises(AppError) as caught:
        _adapter(handler).synthesize("你好")
    assert caught.value.code == "provider_unavailable"


def test_an_empty_body_is_a_failure_not_silence():
    from app.errors import AppError

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, content=b"")

    with pytest.raises(AppError):
        _adapter(handler).synthesize("你好")


def test_a_truncated_stream_is_a_failure():
    from app.errors import AppError

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, content=TRUNCATED_WAV)

    with pytest.raises(AppError):
        _adapter(handler).synthesize("你好")


def test_an_html_error_page_is_a_failure():
    from app.errors import AppError

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, content=b"<html>proxy</html>")

    with pytest.raises(AppError):
        _adapter(handler).synthesize("你好")


def test_the_key_is_never_echoed_in_an_error():
    from app.errors import AppError

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(401, text=f"bad key {API_KEY}")

    with pytest.raises(AppError) as caught:
        _adapter(handler).synthesize("你好")
    assert API_KEY not in str(caught.value)


# -- pure helpers ---------------------------------------------------------
def test_voice_mapping_covers_the_names_we_already_store():
    assert resolve_voice(None) == "stella"
    assert resolve_voice("") == "stella"
    assert resolve_voice("stella") == "stella"
    assert resolve_voice("tide") == "tide"
    assert resolve_voice("zh-CN-XiaoxiaoNeural") == "stella"
    assert resolve_voice("zh-CN-YunxiNeural") == "tide"
    assert resolve_voice("whatever") == "stella"


def test_a_streamed_placeholder_header_is_repaired():
    # What the API really sends: 0xFFFFFFFF for both sizes (measured 2026-11-14).
    streamed = bytearray(WAV)
    streamed[4:8] = (0xFFFFFFFF).to_bytes(4, "little")
    streamed[40:44] = (0xFFFFFFFF).to_bytes(4, "little")
    fixed = normalize_wav(bytes(streamed))
    assert int.from_bytes(fixed[4:8], "little") == len(fixed) - 8
    assert int.from_bytes(fixed[40:44], "little") == len(fixed) - 44
    assert fixed[0:4] == b"RIFF" and fixed[8:12] == b"WAVE"


def test_a_correct_header_is_left_alone():
    assert normalize_wav(WAV) == WAV


def test_wav_detection_rejects_non_wav_and_short_bodies():
    assert wav_from_bytes(WAV) is True
    assert wav_from_bytes(TRUNCATED_WAV) is False
    assert wav_from_bytes(b"") is False
    assert wav_from_bytes(b"ID3" + b"\x00" * 100) is False


# -- the route: primary + fallback ---------------------------------------
class _FakeVoice:
    def __init__(self, media_type: str, audio: bytes = WAV, error=None):
        self.media_type = media_type
        self.audio = audio
        self.error = error
        self.calls: list[tuple[str, str | None, str | None]] = []

    def synthesize(self, text, voice=None, rate=None):
        self.calls.append((text, voice, rate))
        if self.error is not None:
            raise self.error
        return self.audio


def test_the_backend_prefers_the_primary_voice():
    primary = _FakeVoice("audio/wav")
    fallback = _FakeVoice("audio/mpeg", audio=b"ID3mp3")
    backend = tts_api.SpeechBackend(primary=primary, fallback=fallback)

    assert backend.synthesize("你好") == WAV
    assert backend.media_type == "audio/wav"
    assert backend.spoken_with == "deepseek"
    assert fallback.calls == []


def test_a_failing_primary_falls_back_to_edge_and_says_so():
    from app.errors import provider_unavailable

    primary = _FakeVoice("audio/wav", error=provider_unavailable("busy"))
    fallback = _FakeVoice("audio/mpeg", audio=b"ID3mp3")
    backend = tts_api.SpeechBackend(primary=primary, fallback=fallback)

    assert backend.synthesize("你好", rate="-12%") == b"ID3mp3"
    assert backend.media_type == "audio/mpeg"
    assert backend.spoken_with == "edge"
    # The slow pace is still honoured by the adapter that can honour it.
    assert fallback.calls[0][2] == "-12%"


def test_both_voices_failing_is_the_honest_503():
    from app.errors import AppError, provider_unavailable

    backend = tts_api.SpeechBackend(
        primary=_FakeVoice("audio/wav", error=provider_unavailable("busy")),
        fallback=_FakeVoice("audio/mpeg", error=provider_unavailable("busy too")),
    )
    with pytest.raises(AppError) as caught:
        backend.synthesize("你好")
    assert caught.value.code == "provider_unavailable"


# -- provider selection from the environment -----------------------------
def test_a_key_means_deepseek_and_no_key_means_edge(monkeypatch):
    monkeypatch.delenv("ANCHOR_TTS_PROVIDER", raising=False)
    monkeypatch.setenv("ANCHOR_LLM_API_KEY", API_KEY)
    monkeypatch.delenv("ANCHOR_TTS_API_KEY", raising=False)
    assert tts_api.build_backend().name == "deepseek"

    monkeypatch.delenv("ANCHOR_LLM_API_KEY")
    monkeypatch.delenv("ANCHOR_TTS_API_KEY", raising=False)
    assert tts_api.build_backend().name == "edge"


def test_the_provider_can_be_forced_to_edge_even_with_a_key(monkeypatch):
    monkeypatch.setenv("ANCHOR_LLM_API_KEY", API_KEY)
    monkeypatch.setenv("ANCHOR_TTS_PROVIDER", "edge")
    assert tts_api.build_backend().name == "edge"


def test_a_dedicated_tts_key_is_used_when_present(monkeypatch):
    monkeypatch.delenv("ANCHOR_LLM_API_KEY", raising=False)
    monkeypatch.setenv("ANCHOR_TTS_API_KEY", "sk-tts-only")
    backend = tts_api.build_backend()
    assert backend.name == "deepseek"
