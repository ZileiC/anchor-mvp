"""Consent follows the authenticated senior at each cloud speech boundary."""

from unittest.mock import Mock

import pytest

from app.api import providers, tts
from app.errors import provider_unavailable
from app.providers.asr_windows import WindowsSapiASR
from app.providers.config import ProviderConfig
from tests.helpers import headers, link_relationship, seed_consents

AUDIO = {"audio_b64": "c3ludGhldGlj"}
TEXT = {"text": "Synthetic conversation text"}


@pytest.fixture
def cloud_adapters(app, monkeypatch):
    asr = Mock()
    asr.transcribe.return_value = "Synthetic transcript"
    primary = Mock(media_type="audio/wav")
    primary.synthesize.return_value = b"synthetic wav"
    fallback = Mock(media_type="audio/mpeg")
    fallback.synthesize.return_value = b"synthetic mp3"
    llm = Mock()
    llm.reply.return_value = "Synthetic reply"

    ctx = app.state.ctx
    ctx.providers.update(asr=asr, llm=llm)
    backend = tts.SpeechBackend(primary, fallback)
    app.dependency_overrides[tts.get_tts] = lambda: backend
    monkeypatch.setattr(providers, "build_llm", lambda *args, **kwargs: llm)
    monkeypatch.setattr(
        providers, "resolve_llm", lambda *args: ProviderConfig("http", "https://example.test")
    )
    return asr, primary, fallback, llm


def set_cloud_consent(client, token, allowed):
    auth = headers(token)
    version = client.get("/api/v1/consents", headers=auth).json()["version"]
    result = client.put(
        "/api/v1/consents",
        headers=auth,
        json={
            "base_version": version,
            "changes": [{"capability": "cloud_processing", "allowed": allowed}],
        },
    )
    assert result.status_code == 200, result.text


@pytest.mark.parametrize(
    ("route", "body", "caller"),
    [
        ("/transcribe", AUDIO, "senior"),
        ("/tts", TEXT, "senior"),
        ("/tts", TEXT, "caregiver"),
        ("/providers/test", AUDIO, "senior"),
        ("/providers/test", AUDIO, "caregiver"),
        ("/providers/test", {}, "caregiver"),
    ],
)
def test_cloud_speech_tracks_current_consent(
    client, app, make_user, senior_token, caregiver_token, linked, cloud_adapters,
    route, body, caller,
):
    # Another household's permission and a client-supplied id never grant access.
    unrelated = make_user("senior", "Other senior")
    seed_consents(app, unrelated, cloud_processing=True)
    token = senior_token if caller == "senior" else caregiver_token
    asr, primary, fallback, llm = cloud_adapters
    payload = {**body, "senior_id": unrelated["id"]}
    for allowed in (False, True, False, True):
        set_cloud_consent(client, senior_token, allowed)
        for adapter in cloud_adapters:
            adapter.reset_mock()
        response = client.post("/api/v1" + route, headers=headers(token), json=payload)
        if route == "/providers/test":
            assert response.status_code == 200
            result = response.json()
            expected = (("llm", True), ("asr", bool(body)))
            for name, requested in expected:
                probe = result[name]
                assert probe["ok"] is (allowed and requested)
                if not requested:
                    assert probe["reason"] == "no_sample"
                elif not allowed:
                    assert probe["reason"] == "consent_required"
        elif allowed:
            assert response.status_code == 200, response.text
        else:
            assert response.status_code == 403, response.text
            assert response.json()["error"]["code"] == "consent_required"

        assert asr.transcribe.call_count == int(
            allowed and bool(body) and route in ("/transcribe", "/providers/test")
        )
        assert primary.synthesize.call_count == int(allowed and route == "/tts")
        fallback.synthesize.assert_not_called()
        assert llm.reply.call_count == int(allowed and route == "/providers/test")


def test_caregiver_speech_requires_an_accepted_link(
    client, app, senior, caregiver, senior_token, caregiver_token, cloud_adapters,
):
    set_cloud_consent(client, senior_token, True)
    auth = headers(caregiver_token)
    routes = (("/tts", TEXT), ("/providers/test", AUDIO))
    for path, body in routes:
        response = client.post("/api/v1" + path, headers=auth, json=body)
        assert response.status_code == 403 and response.json()["error"]["code"] == "forbidden"
    # Passing cloud consent cannot give a caregiver access to the senior-only route.
    link = link_relationship(app, senior, caregiver, status="accepted")
    assert client.post("/api/v1/transcribe", headers=auth, json=AUDIO).status_code == 403
    revoked = client.delete(
        f"/api/v1/relationships/{link['id']}", headers=headers(senior_token)
    )
    assert revoked.status_code == 200
    for path, body in routes:
        response = client.post("/api/v1" + path, headers=auth, json=body)
        assert response.status_code == 403 and response.json()["error"]["code"] == "forbidden"
    for adapter in cloud_adapters:
        assert adapter.method_calls == []


def test_local_windows_asr_works_without_cloud_consent(client, app, senior_token):
    calls = []

    def run(wav, output):
        calls.append(wav.read_bytes())
        output.write_text("Local transcript", encoding="utf-8")
        return 0

    app.state.ctx.providers["asr"] = WindowsSapiASR(runner=run)
    auth = headers(senior_token)
    # Synthetic WAV signature, sufficient for the adapter with a stub runner.
    audio = {"audio_b64": "UklGRgAAAABXQVZF" + "AAAA" * 16}
    response = client.post("/api/v1/transcribe", headers=auth, json=audio)
    assert response.json() == {"text": "Local transcript", "provider": "windows-sapi"}
    result = client.post("/api/v1/providers/test", headers=auth, json=audio).json()
    assert result["asr"]["text_sample"] == "Local transcript"
    assert len(calls) == 2


def test_revocation_after_transcription_blocks_llm_and_preserves_stop(
    client, senior_token, cloud_adapters,
):
    auth = headers(senior_token)
    set_cloud_consent(client, senior_token, True)
    opened = client.post("/api/v1/sessions", headers=auth, json={"origin": "voluntary"})
    session_path = "/api/v1/sessions/" + opened.json()["session_id"]
    asr, _, _, llm = cloud_adapters

    def transcribe(*args):
        set_cloud_consent(client, senior_token, False)
        return "Synthetic transcript"

    asr.transcribe.side_effect = transcribe
    reply = client.post(session_path + "/turns", headers=auth, json=AUDIO)
    assert reply.status_code == 403 and reply.json()["error"]["code"] == "consent_required"
    asr.transcribe.assert_called_once()
    llm.reply.assert_not_called()
    stopped = client.post(session_path + "/stop", headers=auth)
    assert stopped.status_code == 200 and stopped.json()["state"] == "stopped"


def test_revocation_before_tts_fallback_blocks_second_cloud_provider(
    client, senior_token, cloud_adapters,
):
    _, primary, fallback, _ = cloud_adapters
    set_cloud_consent(client, senior_token, True)

    # The ordinary permitted fallback remains available.
    primary.synthesize.side_effect = provider_unavailable("Synthetic provider failure")
    result = client.post("/api/v1/tts", headers=headers(senior_token), json=TEXT)
    assert result.status_code == 200 and result.headers["X-Anchor-Voice"] == "edge"
    fallback.synthesize.assert_called_once()
    fallback.reset_mock()

    def fail_after_revocation(*args, **kwargs):
        set_cloud_consent(client, senior_token, False)
        raise provider_unavailable("Synthetic provider failure")

    primary.synthesize.side_effect = fail_after_revocation
    result = client.post("/api/v1/tts", headers=headers(senior_token), json=TEXT)
    assert result.status_code == 403 and result.json()["error"]["code"] == "consent_required"
    fallback.synthesize.assert_not_called()


def test_revocation_between_provider_probes_blocks_cloud_asr(
    client, senior_token, caregiver_token, linked, cloud_adapters,
):
    asr, _, _, llm = cloud_adapters
    set_cloud_consent(client, senior_token, True)

    def reply(*args, **kwargs):
        set_cloud_consent(client, senior_token, False)
        return "Synthetic reply"

    llm.reply.side_effect = reply
    result = client.post("/api/v1/providers/test", headers=headers(caregiver_token), json=AUDIO)
    assert result.status_code == 200
    assert result.json()["llm"]["ok"] is True
    assert result.json()["asr"]["reason"] == "consent_required"
    asr.transcribe.assert_not_called()
