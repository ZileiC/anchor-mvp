"""Provider settings API: authz, masking, partial edits, live rebuild, honesty.

No test here performs a network call: the HTTP adapters receive an
``httpx.MockTransport`` through ``AppContext.provider_transport``.
"""

from __future__ import annotations

import base64

import httpx
import pytest
from fastapi.testclient import TestClient

from app.main import create_app
from app.providers.asr_fake import FakeASR
from app.providers.asr_http import HttpASR
from app.providers.config import load_provider_settings, mask_key
from app.providers.llm_http import HttpLLM
from app.providers.unavailable import UnavailableASR
from tests.helpers import headers, seed_consents

RAW_KEY = "sk-live-abcdefghijklmnop-1234"
WAV_BYTES = b"RIFF" + b"\x00" * 4 + b"WAVE" + b"fmt " + b"\x00" * 32 + b"data" + b"\x00" * 8


def _put(client, token, body):
    return client.put("/api/v1/providers", json=body, headers=headers(token))


def _configure_llm(client, token, *, model="deepseek-chat"):
    return _put(
        client,
        token,
        {
            "llm": {
                "base_url": "https://api.deepseek.com",
                "api_key": RAW_KEY,
                "model": model,
            }
        },
    )


def _grant(app, senior):
    seed_consents(app, senior, cloud_processing=True, record_observations=False)


def _open_session(client, token):
    return client.post("/api/v1/sessions", json={"origin": "voluntary"}, headers=headers(token))


# -- authz -----------------------------------------------------------------
def test_providers_endpoints_require_a_token(client):
    assert client.get("/api/v1/providers").status_code == 401
    assert client.put("/api/v1/providers", json={"llm": {"model": "x"}}).status_code == 401
    assert client.post("/api/v1/providers/test", json={}).status_code == 401


def test_a_linked_caregiver_may_configure_the_providers(
    client, caregiver_token, linked
):
    """AI 接入 is device configuration the family sets up (2026-11-11).

    The older adult's privacy is consents, memories, conversations and what gets
    shared — not which model string the appliance dials. A connected family
    member configures it on the phone, so all three verbs work for them.
    """
    assert (
        client.get("/api/v1/providers", headers=headers(caregiver_token)).status_code
        == 200
    )
    saved = _configure_llm(client, caregiver_token, model="deepseek-flash")
    assert saved.status_code == 200, saved.text
    assert saved.json()["llm"]["configured"] is True
    assert saved.json()["llm"]["model"] == "deepseek-flash"
    assert (
        client.post(
            "/api/v1/providers/test", json={}, headers=headers(caregiver_token)
        ).status_code
        == 200
    )


def test_an_unlinked_caregiver_cannot_configure_the_providers(
    client, caregiver_token
):
    # An account with no accepted link is a stranger with a token.
    for response in (
        client.get("/api/v1/providers", headers=headers(caregiver_token)),
        _put(client, caregiver_token, {"llm": {"model": "x"}}),
        client.post("/api/v1/providers/test", json={}, headers=headers(caregiver_token)),
    ):
        assert response.status_code == 403
        assert response.json()["error"]["code"] == "forbidden"


# -- read is honest --------------------------------------------------------
def test_get_providers_reports_not_configured(client, senior_token):
    response = client.get("/api/v1/providers", headers=headers(senior_token))
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["llm"]["configured"] is False
    assert body["llm"]["mode"] == "offline"
    assert body["llm"]["engine"] == "offline-rule"
    assert body["llm"]["key_hint"] is None
    assert body["asr"]["configured"] is False
    assert body["asr"]["mode"] == "offline"
    assert body["asr"]["base_url"] is None
    assert body["asr"]["key_hint"] is None
    assert body["updated_at"] is None


# -- masking ---------------------------------------------------------------
def test_key_is_masked_and_never_returned(client, app, senior_token):
    response = _configure_llm(client, senior_token)
    assert response.status_code == 200, response.text
    assert RAW_KEY not in response.text
    llm = response.json()["llm"]
    assert llm["configured"] is True
    assert llm["mode"] == "http"
    assert llm["base_url"] == "https://api.deepseek.com"
    assert llm["key_hint"] and RAW_KEY not in llm["key_hint"]

    fetched = client.get("/api/v1/providers", headers=headers(senior_token))
    assert RAW_KEY not in fetched.text
    assert fetched.json()["llm"]["key_hint"] == llm["key_hint"]

    # Plaintext local storage is a documented limitation of the self-hosted demo.
    row = load_provider_settings(app.state.ctx.db)
    assert row["llm_api_key"] == RAW_KEY
    assert row["llm_base_url"] == "https://api.deepseek.com"


def test_mask_key_never_reveals_the_whole_key():
    assert mask_key(None) is None
    assert mask_key("") is None
    assert mask_key("abcd") == "…"
    hint = mask_key(RAW_KEY)
    assert hint and RAW_KEY not in hint
    assert hint.startswith("sk-") and hint.endswith(RAW_KEY[-4:])


# -- partial update / clear ------------------------------------------------
def test_partial_update_keeps_the_stored_key(client, app, senior_token):
    first = _configure_llm(client, senior_token).json()["llm"]
    response = _put(
        client,
        senior_token,
        {"llm": {"model": "deepseek-reasoner"}},
    )
    assert response.status_code == 200, response.text
    second = response.json()["llm"]
    assert second["model"] == "deepseek-reasoner"
    assert second["base_url"] == first["base_url"]
    assert second["key_hint"] == first["key_hint"]
    assert second["configured"] is True

    # an explicitly empty api_key keeps the stored key too
    _put(client, senior_token, {"llm": {"api_key": "   "}})
    assert load_provider_settings(app.state.ctx.db)["llm_api_key"] == RAW_KEY


def test_clear_removes_a_section(client, app, senior_token):
    _configure_llm(client, senior_token)
    response = _put(client, senior_token, {"llm": {"clear": True}})
    assert response.status_code == 200, response.text
    llm = response.json()["llm"]
    assert llm["configured"] is False
    assert llm["base_url"] is None
    assert llm["key_hint"] is None
    assert llm["mode"] == "offline"
    row = load_provider_settings(app.state.ctx.db)
    assert row["llm_base_url"] is None
    assert row["llm_api_key"] is None
    assert row["llm_model"] is None


def test_asr_section_is_stored_and_masked_too(client, senior_token):
    response = _put(
        client,
        senior_token,
        {
            "asr": {
                "base_url": "https://asr.example/v1",
                "api_key": "asr-secret-key-0001",
                "model": "whisper-1",
            }
        },
    )
    assert response.status_code == 200, response.text
    assert "asr-secret-key-0001" not in response.text
    asr = response.json()["asr"]
    assert asr["configured"] is True
    assert asr["mode"] == "http"
    assert asr["base_url"] == "https://asr.example/v1"
    assert asr["key_hint"]


# -- validation ------------------------------------------------------------
@pytest.mark.parametrize(
    "section",
    [
        {"llm": {"base_url": "ftp://api.example", "api_key": "k"}},
        {"llm": {"base_url": "not-a-url", "api_key": "k"}},
        {"asr": {"base_url": "ws://asr.example"}},
    ],
)
def test_invalid_urls_are_rejected(client, app, senior_token, section):
    response = _put(client, senior_token, section)
    assert response.status_code == 422, response.text
    assert response.json()["error"]["code"] == "validation_error"
    assert load_provider_settings(app.state.ctx.db) is None


@pytest.mark.parametrize("name", ["llm", "asr"])
def test_empty_model_is_rejected(client, app, senior_token, name):
    response = _put(
        client,
        senior_token,
        {name: {"base_url": "https://example.test", "model": "   "}},
    )
    assert response.status_code == 422, response.text
    assert response.json()["error"]["code"] == "validation_error"


# -- live rebuild ----------------------------------------------------------
def test_put_rebuilds_in_place_and_the_orchestrator_uses_the_http_adapter(
    client, app, senior, senior_token
):
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json={"choices": [{"message": {"content": "你好呀，我在呢。"}}]})

    app.state.ctx.provider_transport = httpx.MockTransport(handler)
    providers_before = app.state.ctx.providers
    orchestrator_providers = app.state.ctx.conversation.providers
    assert orchestrator_providers is providers_before

    assert _configure_llm(client, senior_token).status_code == 200

    assert app.state.ctx.providers is providers_before  # same dict object
    assert app.state.ctx.providers["llm"] is not None
    assert isinstance(app.state.ctx.providers["llm"], HttpLLM)
    assert app.state.ctx.conversation.providers["llm"] is app.state.ctx.providers["llm"]

    _grant(app, senior)
    session = _open_session(client, senior_token).json()
    turn = client.post(
        f"/api/v1/sessions/{session['session_id']}/turns",
        json={"text": "你好"},
        headers=headers(senior_token),
    )
    assert turn.status_code == 200, turn.text
    assert turn.json()["reply_text"] == "你好呀，我在呢。"
    assert seen and seen[-1].headers["authorization"] == f"Bearer {RAW_KEY}"
    assert seen[-1].url.path.endswith("/chat/completions")


def test_put_builds_an_http_asr_adapter(client, app, senior_token):
    app.state.ctx.provider_transport = httpx.MockTransport(
        lambda request: httpx.Response(200, json={"text": "我想喝水"})
    )
    response = _put(
        client,
        senior_token,
        {"asr": {"base_url": "https://asr.example/v1", "api_key": "asr-key-123456"}},
    )
    assert response.status_code == 200, response.text
    assert isinstance(app.state.ctx.providers["asr"], HttpASR)


def test_stored_settings_are_loaded_on_startup(settings, fake_clock, senior, senior_token, client):
    assert _configure_llm(client, senior_token).status_code == 200
    restarted = create_app(settings, clock=fake_clock)
    try:
        assert isinstance(restarted.state.ctx.providers["llm"], HttpLLM)
        fresh_client = TestClient(restarted)
        body = fresh_client.get("/api/v1/providers", headers=headers(senior_token)).json()
        assert body["llm"]["configured"] is True
        assert body["llm"]["base_url"] == "https://api.deepseek.com"
        assert RAW_KEY not in str(body)
    finally:
        restarted.state.db.close()


# -- honest not-configured behaviour --------------------------------------
def test_none_mode_asr_returns_honest_503_and_writes_nothing(client, app, senior, senior_token):
    assert isinstance(app.state.ctx.providers["asr"], UnavailableASR)
    _grant(app, senior)
    session = _open_session(client, senior_token).json()
    response = client.post(
        f"/api/v1/sessions/{session['session_id']}/turns",
        json={"audio_b64": base64.b64encode(WAV_BYTES).decode("ascii"), "audio_mime": "audio/wav"},
        headers=headers(senior_token),
    )
    assert response.status_code == 503, response.text
    error = response.json()["error"]
    assert error["code"] == "provider_unavailable"
    assert "语音识别还没有接入" in error["message"]
    assert error["recovery"] == ["type_instead", "configure"]
    assert error["provider"] == "asr"
    assert app.state.ctx.db.query("SELECT * FROM turns") == []


def test_none_mode_llm_returns_honest_503(client, app, senior, senior_token):
    from app.providers.unavailable import UnavailableLLM

    app.state.ctx.providers["llm"] = UnavailableLLM()
    _grant(app, senior)
    session = _open_session(client, senior_token).json()
    response = client.post(
        f"/api/v1/sessions/{session['session_id']}/turns",
        json={"text": "你好"},
        headers=headers(senior_token),
    )
    assert response.status_code == 503, response.text
    error = response.json()["error"]
    assert error["code"] == "provider_unavailable"
    assert error["recovery"] == ["type_instead", "configure"]


# -- POST /providers/test --------------------------------------------------
def test_test_endpoint_llm_uses_the_current_config_and_a_canned_transport(
    client, app, senior_token
):
    requests_seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests_seen.append(request)
        return httpx.Response(200, json={"choices": [{"message": {"content": " 你好！"}}]})

    app.state.ctx.provider_transport = httpx.MockTransport(handler)
    assert _configure_llm(client, senior_token).status_code == 200

    response = client.post("/api/v1/providers/test", json={}, headers=headers(senior_token))
    assert response.status_code == 200, response.text
    assert RAW_KEY not in response.text
    result = response.json()["llm"]
    assert result["ok"] is True
    assert result["reply_sample"] == "你好！"
    assert isinstance(result["latency_ms"], int)
    assert result["error"] is None

    payload = requests_seen[-1].read().decode("utf-8")
    assert '"model":"deepseek-chat"' in payload.replace(" ", "")
    assert "Reply with one short sentence." in payload
    assert "你好" in payload
    assert requests_seen[-1].headers["authorization"] == f"Bearer {RAW_KEY}"


def test_test_endpoint_llm_failure_is_reported_without_leaking_the_key(
    client, app, senior_token
):
    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("no route", request=request)

    app.state.ctx.provider_transport = httpx.MockTransport(handler)
    assert _configure_llm(client, senior_token).status_code == 200

    response = client.post("/api/v1/providers/test", json={}, headers=headers(senior_token))
    assert response.status_code == 200, response.text
    assert RAW_KEY not in response.text
    result = response.json()["llm"]
    assert result["ok"] is False
    assert result["reply_sample"] is None
    assert result["error"]
    assert isinstance(result["latency_ms"], int)


def test_test_endpoint_reports_not_configured_instead_of_pretending(client, app, senior_token):
    response = client.post("/api/v1/providers/test", json={}, headers=headers(senior_token))
    result = response.json()
    assert result["llm"]["ok"] is False
    assert "not_configured" in result["llm"]["error"]
    assert result["asr"] == {"ok": False, "reason": "no_sample"}


def test_test_endpoint_asr_without_a_sample_says_no_sample(client, app, senior_token, use_providers):
    use_providers(asr=FakeASR("我想喝水"))
    body = client.post("/api/v1/providers/test", json={}, headers=headers(senior_token)).json()
    assert body["asr"] == {"ok": False, "reason": "no_sample"}


def test_test_endpoint_asr_transcribes_a_supplied_sample(client, app, senior_token, use_providers):
    use_providers(asr=FakeASR("我想喝水"))
    response = client.post(
        "/api/v1/providers/test",
        json={"audio_b64": base64.b64encode(WAV_BYTES).decode("ascii"), "audio_mime": "audio/wav"},
        headers=headers(senior_token),
    )
    assert response.status_code == 200, response.text
    result = response.json()["asr"]
    assert result["ok"] is True
    assert result["text_sample"] == "我想喝水"
    assert result["error"] is None


def test_test_endpoint_asr_unconfigured_is_honest(client, app, senior_token):
    response = client.post(
        "/api/v1/providers/test",
        json={"audio_b64": base64.b64encode(WAV_BYTES).decode("ascii")},
        headers=headers(senior_token),
    )
    result = response.json()["asr"]
    assert result["ok"] is False
    assert "语音识别还没有接入" in result["error"]


def test_test_endpoint_asr_rejects_bad_base64(client, senior_token):
    response = client.post(
        "/api/v1/providers/test",
        json={"audio_b64": "not base64!!"},
        headers=headers(senior_token),
    )
    result = response.json()["asr"]
    assert result == {
        "ok": False,
        "reason": "invalid_sample",
        "error": "audio_b64 is not valid base64",
    }
