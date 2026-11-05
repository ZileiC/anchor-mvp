"""Memory lifecycle, retrieval and privacy (SPEC §6.4, surface ``s2_``).

Includes the §8 failure test ``failure_delete_memory`` and the seven-day recall.
"""

from __future__ import annotations

from tests.helpers import RecordingLLM, headers, seed_consents

FACT = "养过一只叫小黑的猫"


def _grant(app, senior, *, memory=True, cloud=True):
    seed_consents(app, senior, save_memory=memory, cloud_processing=cloud)


def _propose(client, token, fact=FACT):
    return client.post("/api/v1/memories", json={"fact": fact}, headers=headers(token))


def test_memory_requires_consent(client, app, senior, senior_token):
    response = _propose(client, senior_token)
    assert response.status_code == 403
    assert response.json()["error"]["code"] == "consent_required"


def test_memory_length_validation(client, app, senior, senior_token):
    _grant(app, senior)
    assert _propose(client, senior_token, "短").status_code == 422
    assert _propose(client, senior_token, "长" * 201).status_code == 422
    assert _propose(client, senior_token, "  " + FACT + "  ").status_code == 200


def test_memory_propose_then_approve(client, app, senior, senior_token):
    _grant(app, senior)
    proposed = _propose(client, senior_token).json()
    assert proposed["approval_state"] == "proposed"
    assert proposed["fact"] == FACT

    listed = client.get("/api/v1/memories", headers=headers(senior_token)).json()
    assert [item["approval_state"] for item in listed["items"]] == ["proposed"]

    approved = client.post(
        f"/api/v1/memories/{proposed['id']}/approve", headers=headers(senior_token)
    )
    assert approved.status_code == 200
    assert approved.json()["approval_state"] == "approved"
    assert approved.json()["approved_at"]

    listed = client.get("/api/v1/memories", headers=headers(senior_token)).json()
    assert listed["items"][0]["approval_state"] == "approved"

    audit = app.state.ctx.db.query("SELECT * FROM audit_events WHERE action = 'memory_approved'")
    assert len(audit) == 1
    assert audit[0]["target_id"] == str(proposed["id"])
    assert FACT not in " ".join(str(value) for value in audit[0].values())


def test_memory_approve_is_idempotent(client, app, senior, senior_token):
    _grant(app, senior)
    memory = _propose(client, senior_token).json()
    first = client.post(f"/api/v1/memories/{memory['id']}/approve", headers=headers(senior_token))
    second = client.post(f"/api/v1/memories/{memory['id']}/approve", headers=headers(senior_token))
    assert first.status_code == 200
    assert second.status_code == 200
    assert second.json()["approved_at"] == first.json()["approved_at"]


def test_memory_delete_removes_row(client, app, senior, senior_token):
    _grant(app, senior)
    memory = _propose(client, senior_token).json()
    response = client.delete(f"/api/v1/memories/{memory['id']}", headers=headers(senior_token))
    assert response.status_code == 200
    assert response.json() == {"id": memory["id"], "deleted": True}
    assert client.get("/api/v1/memories", headers=headers(senior_token)).json()["items"] == []
    assert app.state.ctx.db.query("SELECT * FROM memories") == []
    audit = app.state.ctx.db.query("SELECT * FROM audit_events WHERE action = 'memory_deleted'")
    assert len(audit) == 1
    assert FACT not in " ".join(str(value) for value in audit[0].values())


def test_memory_ownership(client, app, make_user, senior, senior_token):
    from tests.helpers import token_for

    _grant(app, senior)
    memory = _propose(client, senior_token).json()
    stranger = make_user("senior", display_name="别人")
    response = client.delete(
        f"/api/v1/memories/{memory['id']}", headers=headers(token_for(app, stranger))
    )
    assert response.status_code == 404


def test_memory_recall_7d(client, app, senior, senior_token, clock):
    """Approved fact is still recalled seven days later (SPEC §6.4)."""
    seed_consents(app, senior, cloud_processing=True, save_memory=True)
    memory = _propose(client, senior_token).json()
    client.post(f"/api/v1/memories/{memory['id']}/approve", headers=headers(senior_token))

    clock.advance(days=7)
    from tests.helpers import token_for

    fresh_token = token_for(app, senior)  # the dev token expired inside the seven days
    session = client.post(
        "/api/v1/sessions", json={"origin": "voluntary"}, headers=headers(fresh_token)
    ).json()
    body = client.post(
        f"/api/v1/sessions/{session['session_id']}/turns",
        json={"text": "小黑今天怎么样"},
        headers=headers(fresh_token),
    ).json()
    assert "小黑" in body["reply_text"]
    assert body["reply_text"].startswith("我记得你说过")


def test_failure_delete_memory(client, app, senior, senior_token, use_providers):
    """A deleted memory must never reach a prompt or a reply."""
    seed_consents(app, senior, cloud_processing=True, save_memory=True)
    recorder = RecordingLLM("好的。")
    use_providers(llm=recorder)

    memory = _propose(client, senior_token).json()
    client.post(f"/api/v1/memories/{memory['id']}/approve", headers=headers(senior_token))
    client.delete(f"/api/v1/memories/{memory['id']}", headers=headers(senior_token))

    session = client.post(
        "/api/v1/sessions", json={"origin": "voluntary"}, headers=headers(senior_token)
    ).json()
    body = client.post(
        f"/api/v1/sessions/{session['session_id']}/turns",
        json={"text": "小黑今天怎么样"},
        headers=headers(senior_token),
    ).json()

    assert "小黑" not in body["reply_text"]
    assert recorder.calls, "the model should still be called"
    assert "小黑" not in recorder.calls[-1]["system"]
    assert (
        app.state.ctx.memory.retrieve(int(senior["id"]), "小黑今天怎么样", []) == []
    )


def test_proposed_memory_is_not_used(client, app, senior, senior_token, use_providers):
    seed_consents(app, senior, cloud_processing=True, save_memory=True)
    recorder = RecordingLLM("好的。")
    use_providers(llm=recorder)
    _propose(client, senior_token)  # stays proposed
    session = client.post(
        "/api/v1/sessions", json={"origin": "voluntary"}, headers=headers(senior_token)
    ).json()
    client.post(
        f"/api/v1/sessions/{session['session_id']}/turns",
        json={"text": "小黑今天怎么样"},
        headers=headers(senior_token),
    )
    assert "小黑" not in recorder.calls[-1]["system"]


def test_retrieval_limited_to_five(client, app, senior, senior_token):
    _grant(app, senior)
    for index in range(7):
        memory = _propose(client, senior_token, f"喜欢第{index}种花").json()
        client.post(f"/api/v1/memories/{memory['id']}/approve", headers=headers(senior_token))
    recalled = app.state.ctx.memory.retrieve(int(senior["id"]), "花", [])
    assert len(recalled) == 5


def test_caregiver_cannot_read_memories(client, app, senior, caregiver, senior_token, caregiver_token):
    from tests.helpers import link_relationship

    _grant(app, senior)
    link_relationship(app, senior, caregiver, status="accepted")
    assert client.get("/api/v1/memories", headers=headers(caregiver_token)).status_code == 403
    assert _propose(client, caregiver_token).status_code == 403
