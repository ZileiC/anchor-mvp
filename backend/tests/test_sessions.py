"""Conversation sessions: dialogue, captions, recovery, stop and cancellation.

Covers surface tests ``s2_`` (dialogue), ``s4_`` (one-step commands inside a
turn), ``s6_`` (recovery/captions), ``s7_`` (stop) and the §8 failure test
``failure_stop_late_output``.
"""

from __future__ import annotations

from tests.helpers import (
    FailingLLM,
    RecordingLLM,
    StopDuringThinkingLLM,
    headers,
    link_relationship,
    seed_consents,
)


def _grant(app, senior, *, cloud=True, observations=True):
    seed_consents(
        app,
        senior,
        cloud_processing=cloud,
        record_observations=observations,
        save_memory=True,
    )


def _open(client, token, origin="voluntary"):
    response = client.post(
        "/api/v1/sessions", json={"origin": origin}, headers=headers(token)
    )
    return response


def _turn(client, token, session_id, **body):
    return client.post(
        f"/api/v1/sessions/{session_id}/turns", json=body, headers=headers(token)
    )


def test_s2_open_session_requires_cloud_consent(client, app, senior, senior_token):
    response = _open(client, senior_token)
    assert response.status_code == 403
    assert response.json()["error"]["code"] == "consent_required"


def test_s2_open_session_returns_active_state(client, app, senior, senior_token):
    _grant(app, senior)
    response = _open(client, senior_token)
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["state"] == "active"
    assert body["mic_on"] is True
    assert body["session_id"]


def test_s2_open_session_conflict_when_active(client, app, senior, senior_token):
    _grant(app, senior)
    first = _open(client, senior_token).json()
    second = _open(client, senior_token)
    assert second.status_code == 409
    error = second.json()["error"]
    assert error["code"] == "conflict"
    assert error["session_id"] == first["session_id"]


def test_s2_greeting_only_for_proactive_in_window(client, app, senior, senior_token, clock):
    _grant(app, senior)
    proactive = _open(client, senior_token, origin="proactive").json()
    assert proactive.get("greeting_text")
    client.post(
        f"/api/v1/sessions/{proactive['session_id']}/stop", headers=headers(senior_token)
    )

    clock.advance(hours=6)  # 15:00 local -> outside the greeting window
    later = _open(client, senior_token, origin="proactive").json()
    assert "greeting_text" not in later


def test_s2_turn_produces_reply_and_captions(client, app, senior, senior_token):
    _grant(app, senior)
    session = _open(client, senior_token).json()
    response = _turn(client, senior_token, session["session_id"], text="我今天吃了面条")
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["transcript"] == "我今天吃了面条"
    assert body["reply_text"]
    assert body["intent"] == "chat"
    assert body["stopped"] is False
    assert [caption["role"] for caption in body["captions"]] == ["senior", "anchor"]

    turns = app.state.ctx.db.query("SELECT * FROM turns ORDER BY id")
    assert [row["role"] for row in turns] == ["senior", "anchor"]

    observations = app.state.ctx.db.query("SELECT * FROM observations")
    assert len(observations) == 1
    assert observations[0]["topic"] == "meals"
    assert observations[0]["evidence"] == "我今天吃了面条"
    assert observations[0]["event_date"] == "2026-01-05"


def test_s2_observation_skipped_without_consent(client, app, senior, senior_token):
    _grant(app, senior, observations=False)
    session = _open(client, senior_token).json()
    assert _turn(client, senior_token, session["session_id"], text="我今天吃了面条").status_code == 200
    assert app.state.ctx.db.query("SELECT * FROM observations") == []


def test_s2_observation_topic_filtered_by_preferences(client, app, senior, senior_token):
    _grant(app, senior)
    app.state.ctx.preferences.patch(int(senior["id"]), {"observation_topics": ["mood"]})
    session = _open(client, senior_token).json()
    _turn(client, senior_token, session["session_id"], text="我今天吃了面条")
    assert app.state.ctx.db.query("SELECT * FROM observations") == []


def test_s2_repeat_replays_last_answer(client, app, senior, senior_token):
    _grant(app, senior)
    session = _open(client, senior_token).json()
    first = _turn(client, senior_token, session["session_id"], text="今天天气不错").json()
    repeated = _turn(client, senior_token, session["session_id"], text="再说一遍").json()
    assert repeated["intent"] == "repeat"
    assert repeated["reply_text"] == first["reply_text"]


def test_s2_history_is_capped(client, app, senior, senior_token, use_providers):
    _grant(app, senior)
    recorder = RecordingLLM("好呀。")
    use_providers(llm=recorder)
    session = _open(client, senior_token).json()
    for index in range(8):
        _turn(client, senior_token, session["session_id"], text=f"第{index}句话")
    assert len(recorder.calls) == 8
    # 6 stored turns of history + the current utterance.
    assert len(recorder.calls[-1]["turns"]) == 7


def test_s2_diagnostic_reply_is_replaced(client, app, senior, senior_token, use_providers):
    _grant(app, senior)
    use_providers(llm=RecordingLLM("你可能是痴呆，评分很低。"))
    session = _open(client, senior_token).json()
    body = _turn(client, senior_token, session["session_id"], text="我今天有点累").json()
    assert "痴呆" not in body["reply_text"]
    assert "评分" not in body["reply_text"]


def test_s6_audio_turn_uses_transcript_without_persisting_audio(
    client, app, senior, senior_token, use_providers
):
    from app.providers.asr_fake import FakeASR

    _grant(app, senior)
    use_providers(asr=FakeASR("我想喝水"))
    session = _open(client, senior_token).json()
    response = _turn(
        client,
        senior_token,
        session["session_id"],
        audio_b64="aGVsbG8=",
        audio_mime="audio/wav",
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["transcript"] == "我想喝水"
    turns = app.state.ctx.db.query("SELECT text FROM turns")
    assert [row["text"] for row in turns][0] == "我想喝水"
    assert "aGVsbG8=" not in str(
        app.state.ctx.db.query("SELECT * FROM audit_events")
    )


def test_s6_provider_failure_is_recoverable(client, app, senior, senior_token, use_providers):
    from app.providers.asr_fake import FailingASR

    _grant(app, senior)
    use_providers(asr=FailingASR())
    session = _open(client, senior_token).json()
    response = _turn(
        client, senior_token, session["session_id"], audio_b64="aGVsbG8=", audio_mime="audio/wav"
    )
    assert response.status_code == 503
    error = response.json()["error"]
    assert error["code"] == "provider_unavailable"
    assert "type_instead" in error["recovery"]
    assert app.state.ctx.db.query("SELECT * FROM turns") == []

    typed = _turn(client, senior_token, session["session_id"], text="我今天吃了面条")
    assert typed.status_code == 200


def test_s6_invalid_audio_payload(client, app, senior, senior_token):
    _grant(app, senior)
    session = _open(client, senior_token).json()
    response = _turn(client, senior_token, session["session_id"], audio_b64="not base64!!")
    assert response.status_code == 422
    response = _turn(client, senior_token, session["session_id"])
    assert response.status_code == 422


def test_s7_stop_purges_turns_and_is_idempotent(client, app, senior, senior_token):
    _grant(app, senior)
    session = _open(client, senior_token).json()
    _turn(client, senior_token, session["session_id"], text="今天天气不错")

    first = client.post(
        f"/api/v1/sessions/{session['session_id']}/stop", headers=headers(senior_token)
    )
    assert first.status_code == 200
    assert first.json() == {"state": "stopped"}

    second = client.post(
        f"/api/v1/sessions/{session['session_id']}/stop", headers=headers(senior_token)
    )
    assert second.status_code == 200

    view = client.get(
        f"/api/v1/sessions/{session['session_id']}", headers=headers(senior_token)
    ).json()
    assert view["state"] == "stopped"
    assert view["captions"] == []
    assert view["mic_on"] is False
    assert app.state.ctx.db.query("SELECT * FROM turns") == []


def test_s7_turn_after_stop_is_rejected(client, app, senior, senior_token):
    _grant(app, senior)
    session = _open(client, senior_token).json()
    client.post(f"/api/v1/sessions/{session['session_id']}/stop", headers=headers(senior_token))
    response = _turn(client, senior_token, session["session_id"], text="还在吗")
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "session_stopped"


def test_s7_stop_command_inside_turn(client, app, senior, senior_token):
    _grant(app, senior)
    session = _open(client, senior_token).json()
    _turn(client, senior_token, session["session_id"], text="今天天气不错")
    body = _turn(client, senior_token, session["session_id"], text="别说了").json()
    assert body["stopped"] is True
    assert body["intent"] == "stop"
    assert body["action"] == {"type": "stop"}
    assert app.state.ctx.db.query("SELECT * FROM turns") == []
    sessions = app.state.ctx.db.query("SELECT state FROM sessions")
    assert sessions[0]["state"] == "stopped"


def test_failure_stop_late_output(client, app, senior, senior_token, use_providers):
    """Stop during generation: the late model answer must be discarded."""
    _grant(app, senior)
    session = _open(client, senior_token).json()
    late = StopDuringThinkingLLM(app, session["session_id"], senior["id"])
    use_providers(llm=late)

    response = _turn(client, senior_token, session["session_id"], text="慢慢跟我说说")
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["stopped"] is True
    assert body["turn_id"] is None
    assert body["reply_text"] == ""
    assert late.calls == 1

    assert app.state.ctx.db.query("SELECT * FROM turns") == []
    state = app.state.ctx.db.query_one(
        "SELECT state FROM sessions WHERE id = ?", (session["session_id"],)
    )
    assert state["state"] == "stopped"


def test_s4_play_command_returns_activity(client, app, senior, senior_token):
    _grant(app, senior)
    session = _open(client, senior_token).json()
    body = _turn(client, senior_token, session["session_id"], text="玩个游戏吧").json()
    assert body["intent"] == "play"
    assert body["action"]["type"] == "activity"
    activity_id = body["action"]["activity_id"]
    assert app.state.ctx.activities.find(activity_id) is not None


def test_s4_call_command_requires_confirmation(client, app, senior, senior_token):
    from app.clock import iso_utc

    _grant(app, senior)
    app.state.ctx.db.execute(
        "INSERT INTO contacts(senior_id, label, phone, is_family, created_at) VALUES (?,?,?,?,?)",
        (int(senior["id"]), "儿子", "+8613800000000", 1, iso_utc(app.state.ctx.clock.now())),
    )
    session = _open(client, senior_token).json()
    body = _turn(client, senior_token, session["session_id"], text="给儿子打电话").json()
    assert body["intent"] == "call"
    action = body["action"]
    assert action["type"] == "dial"
    assert action["label"] == "儿子"
    assert action["requires_confirmation"] is True
    assert action["phone"] == "+8613800000000"

    actions = app.state.ctx.db.query("SELECT * FROM contact_actions")
    assert len(actions) == 1
    assert actions[0]["confirmed_at"] is None

    audit = app.state.ctx.db.query("SELECT * FROM audit_events WHERE action = 'call_initiated'")
    assert len(audit) == 1


def test_s4_call_command_asks_one_clarification(client, app, senior, senior_token):
    from app.clock import iso_utc

    _grant(app, senior)
    for label, phone in (("儿子", "1"), ("女儿", "2")):
        app.state.ctx.db.execute(
            "INSERT INTO contacts(senior_id, label, phone, is_family, created_at) VALUES (?,?,?,?,?)",
            (int(senior["id"]), label, phone, 1, iso_utc(app.state.ctx.clock.now())),
        )
    session = _open(client, senior_token).json()
    body = _turn(client, senior_token, session["session_id"], text="call").json()
    assert body["intent"] == "call"
    assert body["action"] is None
    assert body["ask"]["kind"] == "clarify"
    assert body["ask"]["options"] == ["儿子", "女儿"]


def test_s4_call_without_contacts(client, app, senior, senior_token):
    _grant(app, senior)
    session = _open(client, senior_token).json()
    body = _turn(client, senior_token, session["session_id"], text="给儿子打电话").json()
    assert body["intent"] == "call"
    assert body["action"] is None
    assert body["ask"] is None


def test_s7_caregiver_cannot_read_conversation(client, app, senior, caregiver, senior_token, caregiver_token):
    _grant(app, senior)
    link_relationship(app, senior, caregiver, status="accepted")
    session = _open(client, senior_token).json()
    response = client.get(
        f"/api/v1/sessions/{session['session_id']}", headers=headers(caregiver_token)
    )
    assert response.status_code == 403
    assert response.json()["error"]["code"] == "caregiver_scope_denied"


def test_s7_other_senior_cannot_read_conversation(client, app, make_user, senior, senior_token):
    from tests.helpers import token_for

    _grant(app, senior)
    session = _open(client, senior_token).json()
    stranger = make_user("senior", display_name="别人")
    response = client.get(
        f"/api/v1/sessions/{session['session_id']}", headers=headers(token_for(app, stranger))
    )
    assert response.status_code == 404


def test_s6_session_view_includes_captions(client, app, senior, senior_token):
    _grant(app, senior)
    session = _open(client, senior_token).json()
    _turn(client, senior_token, session["session_id"], text="今天天气不错")
    view = client.get(
        f"/api/v1/sessions/{session['session_id']}", headers=headers(senior_token)
    ).json()
    assert view["mic_on"] is True
    assert len(view["captions"]) == 2
    assert view["captions"][0]["role"] == "senior"
    assert view["captions"][0]["at"].endswith("Z")


def test_s2_failing_llm_is_recoverable(client, app, senior, senior_token, use_providers):
    _grant(app, senior)
    use_providers(llm=FailingLLM())
    session = _open(client, senior_token).json()
    response = _turn(client, senior_token, session["session_id"], text="今天天气不错")
    assert response.status_code == 503
    assert response.json()["error"]["recovery"] == ["retry", "type_instead"]
    assert app.state.ctx.db.query("SELECT * FROM turns") == []
