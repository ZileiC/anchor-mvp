"""Consent engine endpoints (SPEC §5)."""

from __future__ import annotations

from tests.helpers import headers, seed_consents


def _get(client, token):
    response = client.get("/api/v1/consents", headers=headers(token))
    assert response.status_code == 200, response.text
    return response.json()


def _put(client, token, base_version, changes):
    return client.put(
        "/api/v1/consents",
        json={"base_version": base_version, "changes": changes},
        headers=headers(token),
    )


def test_consents_are_private_by_default(client, senior_token):
    body = _get(client, senior_token)
    assert body["version"] == 1
    assert body["items"] == []


def test_grant_bumps_version_and_writes_audit(client, app, senior, senior_token):
    response = _put(
        client,
        senior_token,
        1,
        [
            {"capability": "cloud_processing", "allowed": True},
            {"capability": "share_topic", "topic": "mood", "allowed": True},
        ],
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["version"] == 2
    by_key = {(item["capability"], item["topic"]): item for item in body["items"]}
    assert by_key[("cloud_processing", "")]["allowed"] is True
    assert by_key[("cloud_processing", "")]["version"] == 2
    assert by_key[("share_topic", "mood")]["allowed"] is True

    audit = app.state.ctx.db.query("SELECT * FROM audit_events ORDER BY id")
    assert len(audit) == 2
    assert {row["action"] for row in audit} == {"consent_granted"}
    assert all(row["target_type"] == "consent" for row in audit)


def test_conflict_on_stale_base_version(client, senior_token):
    assert _put(client, senior_token, 1, [{"capability": "save_memory", "allowed": True}]).status_code == 200
    stale = _put(client, senior_token, 1, [{"capability": "save_memory", "allowed": False}])
    assert stale.status_code == 409
    body = stale.json()["error"]
    assert body["code"] == "consent_version_conflict"
    assert body["current_version"] == 2


def test_share_topic_requires_known_topic(client, senior_token):
    response = _put(
        client, senior_token, 1, [{"capability": "share_topic", "topic": "sleep", "allowed": True}]
    )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"


def test_share_topic_without_topic_rejected(client, senior_token):
    response = _put(client, senior_token, 1, [{"capability": "share_topic", "allowed": True}])
    assert response.status_code == 422


def test_non_topic_capability_rejects_topic(client, senior_token):
    response = _put(
        client,
        senior_token,
        1,
        [{"capability": "cloud_processing", "topic": "mood", "allowed": True}],
    )
    assert response.status_code == 422


def test_unknown_capability_rejected(client, senior_token):
    response = _put(client, senior_token, 1, [{"capability": "everything", "allowed": True}])
    assert response.status_code == 422


def test_identical_change_keeps_version(client, senior_token):
    assert _put(client, senior_token, 1, [{"capability": "save_memory", "allowed": True}]).status_code == 200
    again = _put(client, senior_token, 2, [{"capability": "save_memory", "allowed": True}])
    assert again.status_code == 200
    assert again.json()["version"] == 2


def test_revocation_keeps_row_but_flips_flag(client, senior_token):
    _put(client, senior_token, 1, [{"capability": "cloud_processing", "allowed": True}])
    body = _put(client, senior_token, 2, [{"capability": "cloud_processing", "allowed": False}]).json()
    assert body["version"] == 3
    item = body["items"][0]
    assert item["allowed"] is False
    assert item["version"] == 3


def test_consents_are_per_senior(client, app, make_user, senior, senior_token):
    other = make_user("senior", display_name="另一个老人")
    from tests.helpers import token_for

    _put(client, senior_token, 1, [{"capability": "save_memory", "allowed": True}])
    assert _get(client, token_for(app, other))["items"] == []


def test_consent_requires_senior_role(client, caregiver_token):
    assert client.get("/api/v1/consents", headers=headers(caregiver_token)).status_code == 403
    assert (
        _put(client, caregiver_token, 1, [{"capability": "save_memory", "allowed": True}]).status_code
        == 403
    )


def test_seeded_consents_are_readable(client, app, senior, senior_token):
    seed_consents(
        app,
        senior,
        cloud_processing=True,
        proactive_invitations=True,
        record_observations=True,
        share_topics=("mood", "meals"),
    )
    body = _get(client, senior_token)
    by_key = {(item["capability"], item["topic"]): item for item in body["items"]}
    assert by_key[("cloud_processing", "")]["allowed"] is True
    assert by_key[("share_topic", "mood")]["allowed"] is True
    assert by_key[("share_topic", "activities")]["allowed"] is False
    assert body["version"] == 1
