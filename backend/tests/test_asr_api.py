"""Transcription-only ASR endpoint: ``POST /api/v1/transcribe``.

The route is exercised through the real app with an injected fake adapter, so the
suite never opens a socket and never runs a recognizer. The audio bytes are
opaque to the fake; what matters here is the HTTP contract: the adapter's text
comes back verbatim, bad payloads are a clear 422, provider failures keep the
standard 503 envelope, and the endpoint is senior-only.
"""

from __future__ import annotations

import base64
from typing import Any

import pytest

from app.api.asr import MAX_AUDIO_BYTES
from app.providers.asr_fake import FailingASR, FakeASR
from tests import helpers

URL = "/api/v1/transcribe"
WAV = b"RIFF\x24\x00\x00\x00WAVEfmt " + b"\x00" * 24


@pytest.fixture
def asr(app) -> FakeASR:
    """Inject a deterministic adapter; the fake records what it received."""
    adapter = FakeASR("我今天吃过饭了")
    app.state.ctx.providers["asr"] = adapter
    return adapter


def encode(audio: bytes) -> str:
    return base64.b64encode(audio).decode("ascii")


def post(client, token: str, payload: dict[str, Any]):
    return client.post(URL, json=payload, headers=helpers.headers(token))


# -- success ---------------------------------------------------------------
def test_transcribe_returns_the_adapter_text_verbatim(client, senior_token, asr):
    asr.set_transcript("  我今天吃了面条。  ")

    response = post(client, senior_token, {"audio_b64": encode(WAV)})

    assert response.status_code == 200
    assert response.json()["text"] == "  我今天吃了面条。  "
    assert response.json()["provider"] == "fake"
    assert asr.calls == [(len(WAV), "audio/wav")]


def test_transcribe_accepts_explicit_audio_mime(client, senior_token, asr):
    response = post(
        client,
        senior_token,
        {"audio_b64": encode(WAV), "audio_mime": "audio/wav"},
    )

    assert response.status_code == 200
    assert response.json()["text"] == asr.transcript
    assert asr.calls == [(len(WAV), "audio/wav")]


def test_transcribe_is_transcription_only(client, senior_token, app):
    """The quiz answer must not open a session, call the LLM, or store turns."""
    app.state.ctx.providers["asr"] = FakeASR("四十二")
    llm = helpers.RecordingLLM()
    app.state.ctx.providers["llm"] = llm

    response = post(client, senior_token, {"audio_b64": encode(WAV)})

    assert response.status_code == 200
    assert response.json()["text"] == "四十二"
    assert llm.calls == []
    assert app.state.ctx.db.scalar("SELECT COUNT(*) AS n FROM sessions") == 0
    assert app.state.ctx.db.scalar("SELECT COUNT(*) AS n FROM turns") == 0


# -- payload validation ----------------------------------------------------
@pytest.mark.parametrize("audio_b64", ["not base64!!", "abc$def", "AAAA AAAA"])
def test_transcribe_invalid_base64_is_422(client, senior_token, asr, audio_b64):
    response = post(client, senior_token, {"audio_b64": audio_b64})

    assert response.status_code == 422
    error = response.json()["error"]
    assert error["code"] == "validation_error"
    assert "base64" in error["message"]
    assert asr.calls == []


@pytest.mark.parametrize("audio_b64", ["", None])
def test_transcribe_empty_audio_is_422(client, senior_token, asr, audio_b64):
    response = post(client, senior_token, {"audio_b64": audio_b64})

    assert response.status_code == 422
    error = response.json()["error"]
    assert error["code"] == "validation_error"
    assert "audio_b64" in error["message"]
    assert asr.calls == []


def test_transcribe_missing_audio_is_422(client, senior_token, asr):
    response = post(client, senior_token, {})

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"
    assert asr.calls == []


def test_transcribe_non_string_audio_is_422(client, senior_token, asr):
    response = post(client, senior_token, {"audio_b64": ["not", "bytes"]})

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"
    assert asr.calls == []


def test_transcribe_payload_over_eight_megabytes_is_422(client, senior_token, asr):
    oversized = encode(b"\x00" * (MAX_AUDIO_BYTES + 1))

    response = post(client, senior_token, {"audio_b64": oversized})

    assert response.status_code == 422
    error = response.json()["error"]
    assert error["code"] == "validation_error"
    assert "8 MB" in error["message"]
    assert asr.calls == []


# -- provider failures -----------------------------------------------------
def test_transcribe_provider_failure_is_503_with_the_standard_envelope(
    client, senior_token, app
):
    app.state.ctx.providers["asr"] = FailingASR()

    response = post(client, senior_token, {"audio_b64": encode(WAV)})

    assert response.status_code == 503
    assert response.headers["content-type"].startswith("application/json")
    error = response.json()["error"]
    assert error["code"] == "provider_unavailable"
    assert error["recovery"] == ["retry", "type_instead"]
    assert error["message"]


def test_transcribe_without_a_configured_provider_is_503(client, senior_token):
    # The default test settings resolve to UnavailableASR: the honest 503 stands.
    response = post(client, senior_token, {"audio_b64": encode(WAV)})

    assert response.status_code == 503
    error = response.json()["error"]
    assert error["code"] == "provider_unavailable"
    assert error["recovery"] == ["type_instead", "configure"]


# -- auth ------------------------------------------------------------------
def test_transcribe_caregiver_is_403(client, caregiver_token, asr):
    response = post(client, caregiver_token, {"audio_b64": encode(WAV)})

    assert response.status_code == 403
    assert response.json()["error"]["code"] == "forbidden"
    assert asr.calls == []


def test_transcribe_without_a_token_is_401(client, asr):
    response = client.post(URL, json={"audio_b64": encode(WAV)})

    assert response.status_code == 401
    assert response.json()["error"]["code"] == "unauthorized"
    assert asr.calls == []
