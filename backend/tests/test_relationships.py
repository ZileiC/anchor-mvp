"""Invitations, family links and schedule proposals (SPEC §6.1, s12 setup)."""

from __future__ import annotations

import hashlib

from tests.helpers import (
    headers,
    insert_digest,
    insert_job,
    link_relationship,
)


def _invite(client, senior_token, hours: int | None = None) -> dict:
    body = {} if hours is None else {"expires_in_hours": hours}
    response = client.post("/api/v1/invitations", json=body, headers=headers(senior_token))
    assert response.status_code == 200, response.text
    return response.json()


def _accept(client, caregiver_token, token: str):
    return client.post(
        "/api/v1/invitations/accept", json={"token": token}, headers=headers(caregiver_token)
    )


def test_s12_invite_accept_approve_flow(client, app, senior_token, caregiver_token, caregiver):
    invitation = _invite(client, senior_token)
    assert set(invitation) >= {"id", "token", "expires_at", "accept_path"}
    assert invitation["token"]

    accepted = _accept(client, caregiver_token, invitation["token"])
    assert accepted.status_code == 200, accepted.text
    body = accepted.json()
    assert body["status"] == "pending"

    listed = client.get("/api/v1/relationships", headers=headers(senior_token)).json()["items"]
    assert len(listed) == 1
    assert listed[0]["status"] == "pending"
    assert listed[0]["counterpart_name"] == caregiver["display_name"]

    approved = client.post(
        f"/api/v1/relationships/{body['relationship_id']}/approve",
        headers=headers(senior_token),
    )
    assert approved.status_code == 200, approved.text
    assert approved.json()["status"] == "accepted"

    me = client.get("/api/v1/me", headers=headers(caregiver_token)).json()
    assert me["relationship_status"] == "accepted"
    assert me["senior_id"] is not None

    notifications = app.state.ctx.db.query(
        "SELECT * FROM notifications WHERE user_id = ?", (caregiver["id"],)
    )
    assert len(notifications) == 1
    assert notifications[0]["kind"] == "relationship"


def test_invitation_token_is_hashed_at_rest(client, app, senior_token):
    invitation = _invite(client, senior_token)
    row = app.state.ctx.db.query_one(
        "SELECT * FROM invitations WHERE id = ?", (invitation["id"],)
    )
    assert row["token_hash"] == hashlib.sha256(invitation["token"].encode()).hexdigest()
    assert row["token_hash"] != invitation["token"]


def test_invitation_is_single_use(client, senior_token, caregiver_token):
    invitation = _invite(client, senior_token)
    assert _accept(client, caregiver_token, invitation["token"]).status_code == 200
    second = _accept(client, caregiver_token, invitation["token"])
    assert second.status_code == 410
    assert second.json()["error"]["code"] == "invitation_invalid"


def test_invitation_expires(client, app, senior_token, caregiver_token, clock):
    invitation = _invite(client, senior_token, hours=1)
    clock.advance(hours=2)
    response = _accept(client, caregiver_token, invitation["token"])
    assert response.status_code == 410
    assert response.json()["error"]["code"] == "invitation_invalid"


def test_invitation_rejects_unknown_token(client, caregiver_token):
    response = _accept(client, caregiver_token, "not-a-real-token")
    assert response.status_code == 410
    assert response.json()["error"]["code"] == "invitation_invalid"


def test_invitation_requires_valid_expiry(client, senior_token):
    response = client.post(
        "/api/v1/invitations", json={"expires_in_hours": 0}, headers=headers(senior_token)
    )
    assert response.status_code == 422


def test_accept_requires_caregiver_role(client, app, senior, senior_token):
    from tests.helpers import token_for

    invitation = _invite(client, senior_token)
    senior_2 = token_for(app, senior)
    response = _accept(client, senior_2, invitation["token"])
    assert response.status_code == 403
    assert response.json()["error"]["code"] == "forbidden"


def test_approve_foreign_relationship_is_404(client, app, make_user, caregiver):
    other_senior = make_user("senior", display_name="别人")
    from tests.helpers import token_for

    relationship = link_relationship(app, other_senior, caregiver, status="pending")
    response = client.post(
        f"/api/v1/relationships/{relationship['id']}/approve",
        headers=headers(token_for(app, make_user("senior", display_name="第三个人"))),
    )
    assert response.status_code == 404
    assert response.json()["error"]["code"] == "not_found"


def test_approve_requires_pending_state(client, app, senior, caregiver, senior_token):
    relationship = link_relationship(app, senior, caregiver, status="pending")
    first = client.post(
        f"/api/v1/relationships/{relationship['id']}/approve", headers=headers(senior_token)
    )
    assert first.status_code == 200
    second = client.post(
        f"/api/v1/relationships/{relationship['id']}/approve", headers=headers(senior_token)
    )
    assert second.status_code == 409
    assert second.json()["error"]["code"] == "conflict"


def test_revoke_is_idempotent(client, app, senior, caregiver, senior_token):
    relationship = link_relationship(app, senior, caregiver, status="accepted")
    first = client.delete(
        f"/api/v1/relationships/{relationship['id']}", headers=headers(senior_token)
    )
    assert first.status_code == 200
    assert first.json()["status"] == "revoked"
    second = client.delete(
        f"/api/v1/relationships/{relationship['id']}", headers=headers(senior_token)
    )
    assert second.status_code == 200
    assert second.json()["status"] == "revoked"


def test_revoke_cancels_digests_and_notify_jobs(
    client, app, senior, caregiver, senior_token
):
    relationship = link_relationship(app, senior, caregiver, status="accepted")
    digest_id = insert_digest(app, senior, status="approved")
    insert_job(app, "notify_digest", {"digest_id": digest_id, "senior_id": senior["id"]}, "notify_digest:1")

    response = client.delete(
        f"/api/v1/relationships/{relationship['id']}", headers=headers(senior_token)
    )
    assert response.status_code == 200
    digest = app.state.ctx.db.query_one("SELECT * FROM digests WHERE id = ?", (digest_id,))
    assert digest["status"] == "cancelled"
    jobs = app.state.ctx.db.query("SELECT * FROM jobs WHERE job_type = 'notify_digest'")
    assert jobs == []


def test_schedule_proposal_requires_accepted_link(
    client, app, senior, caregiver, caregiver_token
):
    link_relationship(app, senior, caregiver, status="pending")
    response = client.post(
        "/api/v1/schedule-proposals",
        json={"payload": {"greeting_start": "10:00"}},
        headers=headers(caregiver_token),
    )
    assert response.status_code == 403
    assert response.json()["error"]["code"] == "relationship_inactive"


def test_schedule_proposal_without_link_is_inactive(client, caregiver_token):
    response = client.post(
        "/api/v1/schedule-proposals",
        json={"payload": {"greeting_start": "10:00"}},
        headers=headers(caregiver_token),
    )
    assert response.status_code == 403
    assert response.json()["error"]["code"] == "relationship_inactive"


def test_schedule_proposal_approve_applies_preferences(client, app, linked, senior_token, caregiver_token):
    proposal = client.post(
        "/api/v1/schedule-proposals",
        json={"payload": {"greeting_start": "10:00", "greeting_end": "12:00"}},
        headers=headers(caregiver_token),
    )
    assert proposal.status_code == 200, proposal.text
    proposal_id = proposal.json()["id"]

    senior_view = client.get("/api/v1/schedule-proposals", headers=headers(senior_token)).json()
    assert len(senior_view["items"]) == 1
    assert senior_view["items"][0]["status"] == "pending"
    assert senior_view["items"][0]["payload"]["greeting_start"] == "10:00"

    approved = client.post(
        f"/api/v1/schedule-proposals/{proposal_id}/approve", headers=headers(senior_token)
    )
    assert approved.status_code == 200, approved.text
    assert approved.json()["status"] == "approved"

    prefs = client.get("/api/v1/preferences", headers=headers(senior_token)).json()
    assert prefs["greeting_start"] == "10:00"
    assert prefs["greeting_end"] == "12:00"


def test_schedule_proposal_rejects_field_outside_allowlist(client, linked, caregiver_token):
    response = client.post(
        "/api/v1/schedule-proposals",
        json={"payload": {"language": "en"}},
        headers=headers(caregiver_token),
    )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"


def test_schedule_proposal_rejects_bad_value(client, linked, caregiver_token):
    response = client.post(
        "/api/v1/schedule-proposals",
        json={"payload": {"greeting_start": "25:00"}},
        headers=headers(caregiver_token),
    )
    assert response.status_code == 422


def test_schedule_proposal_double_approve_conflicts(client, linked, senior_token, caregiver_token):
    proposal = client.post(
        "/api/v1/schedule-proposals",
        json={"payload": {"daily_cap": 0}},
        headers=headers(caregiver_token),
    ).json()
    url = f"/api/v1/schedule-proposals/{proposal['id']}/approve"
    assert client.post(url, headers=headers(senior_token)).status_code == 200
    second = client.post(url, headers=headers(senior_token))
    assert second.status_code == 409


def test_caregiver_sees_only_own_proposals(client, app, make_user, linked, caregiver_token):
    other_caregiver = make_user("caregiver", display_name="别的家属")
    from tests.helpers import token_for

    client.post(
        "/api/v1/schedule-proposals",
        json={"payload": {"daily_cap": 1}},
        headers=headers(caregiver_token),
    )
    mine = client.get("/api/v1/schedule-proposals", headers=headers(caregiver_token)).json()
    theirs = client.get(
        "/api/v1/schedule-proposals", headers=headers(token_for(app, other_caregiver))
    ).json()
    assert len(mine["items"]) == 1
    assert theirs["items"] == []
