"""Authorization and privacy suite (SPEC §4, §10: ``authz_*`` >= 15 cases).

Covers role separation, client-supplied id attacks, cross-household access,
revoked relationships and token forgery. Every case calls an endpoint the way an
attacker would and asserts the structured error.
"""

from __future__ import annotations

import pytest

from app.auth import issue_token
from app.clock import iso_utc
from tests.helpers import headers, link_relationship, seed_consents, token_for

SENIOR_ONLY = [
    ("POST", "/api/v1/invitations", {}),
    ("GET", "/api/v1/preferences", None),
    ("PATCH", "/api/v1/preferences", {"paused": True}),
    ("GET", "/api/v1/consents", None),
    ("PUT", "/api/v1/consents", {"base_version": 1, "changes": []}),
    ("GET", "/api/v1/checkins/eligibility", None),
    ("POST", "/api/v1/checkins/attempts", {"device_id": "x", "outcome": "shown"}),
    ("GET", "/api/v1/checkins/schedule", None),
    ("POST", "/api/v1/relationships/1/approve", None),
    ("DELETE", "/api/v1/relationships/1", None),
    ("POST", "/api/v1/schedule-proposals/1/approve", None),
]

CAREGIVER_ONLY = [
    ("POST", "/api/v1/invitations/accept", {"token": "x"}),
    ("POST", "/api/v1/schedule-proposals", {"payload": {"daily_cap": 1}}),
]


@pytest.mark.parametrize("method,path,body", SENIOR_ONLY)
def test_authz_caregiver_cannot_use_senior_endpoint(client, caregiver_token, method, path, body):
    response = client.request(method, path, json=body, headers=headers(caregiver_token))
    assert response.status_code == 403, (path, response.text)
    assert response.json()["error"]["code"] == "forbidden"


@pytest.mark.parametrize("method,path,body", SENIOR_ONLY)
def test_authz_missing_token_is_unauthorized(client, method, path, body):
    response = client.request(method, path, json=body)
    assert response.status_code == 401, (path, response.text)
    assert response.json()["error"]["code"] == "unauthorized"


@pytest.mark.parametrize("method,path,body", CAREGIVER_ONLY)
def test_authz_senior_cannot_use_caregiver_endpoint(client, senior_token, method, path, body):
    response = client.request(method, path, json=body, headers=headers(senior_token))
    assert response.status_code == 403, (path, response.text)
    assert response.json()["error"]["code"] == "forbidden"


@pytest.mark.parametrize("method,path,body", CAREGIVER_ONLY)
def test_authz_caregiver_endpoint_needs_token(client, method, path, body):
    response = client.request(method, path, json=body)
    assert response.status_code == 401


def test_authz_client_supplied_senior_id_is_ignored(client, app, make_user, senior, senior_token):
    """A forged ``senior_id`` field must not change whose consents are written."""
    other = make_user("senior", display_name="别人")
    response = client.put(
        "/api/v1/consents",
        json={
            "base_version": 1,
            "changes": [{"capability": "save_memory", "allowed": True}],
            "senior_id": int(other["id"]),
        },
        headers=headers(senior_token),
    )
    assert response.status_code == 200
    assert app.state.ctx.consent.is_allowed(int(senior["id"]), "save_memory") is True
    assert app.state.ctx.consent.is_allowed(int(other["id"]), "save_memory") is False


def test_authz_cannot_approve_another_households_proposal(client, app, make_user, senior, caregiver, senior_token, caregiver_token):
    other_senior = make_user("senior", display_name="别人")
    seed_consents(app, other_senior)
    link_relationship(app, other_senior, caregiver, status="accepted")
    proposal = client.post(
        "/api/v1/schedule-proposals",
        json={"payload": {"daily_cap": 1}},
        headers=headers(caregiver_token),
    ).json()
    # The proposal belongs to `other_senior`; `senior` must not decide it.
    response = client.post(
        f"/api/v1/schedule-proposals/{proposal['id']}/approve", headers=headers(senior_token)
    )
    assert response.status_code == 404
    assert response.json()["error"]["code"] == "not_found"


def test_authz_cannot_revoke_another_households_relationship(client, app, make_user, senior, caregiver, senior_token):
    other_senior = make_user("senior", display_name="别人")
    relationship = link_relationship(app, other_senior, caregiver, status="accepted")
    response = client.delete(
        f"/api/v1/relationships/{relationship['id']}", headers=headers(senior_token)
    )
    assert response.status_code == 403
    assert response.json()["error"]["code"] == "forbidden"
    still = app.state.ctx.db.query_one(
        "SELECT status FROM relationships WHERE id = ?", (relationship["id"],)
    )
    assert still["status"] == "accepted"


def test_authz_revoked_relationship_blocks_caregiver_actions(client, app, senior, caregiver, caregiver_token):
    relationship = link_relationship(app, senior, caregiver, status="revoked")
    assert relationship["status"] == "revoked"
    response = client.post(
        "/api/v1/schedule-proposals",
        json={"payload": {"daily_cap": 0}},
        headers=headers(caregiver_token),
    )
    assert response.status_code == 403
    assert response.json()["error"]["code"] == "relationship_inactive"


def test_authz_forged_token_signature(client, app, senior):
    token = token_for(app, senior)
    payload = token.split(".")[0]
    forged = issue_token(app.state.ctx.settings.with_(secret="attacker"), senior["id"], "senior", app.state.ctx.clock)[0]
    assert payload in forged  # same payload shape, different signature
    response = client.get("/api/v1/me", headers=headers(forged))
    assert response.status_code == 401


def test_authz_token_for_deleted_account(client, app, make_user):
    ghost = make_user("senior", display_name="幽灵")
    token = token_for(app, ghost)
    app.state.ctx.db.execute("DELETE FROM users WHERE id = ?", (ghost["id"],))
    response = client.get("/api/v1/me", headers=headers(token))
    assert response.status_code == 401


def test_authz_caregiver_only_sees_own_relationship(client, app, make_user, senior, caregiver, caregiver_token):
    other_caregiver = make_user("caregiver", display_name="别的家属")
    link_relationship(app, senior, caregiver, status="accepted")
    link_relationship(app, senior, other_caregiver, status="accepted")
    items = client.get("/api/v1/relationships", headers=headers(caregiver_token)).json()["items"]
    assert len(items) == 1
    assert items[0]["caregiver_id"] == caregiver["id"]


def test_authz_senior_relationship_list_only_own(client, app, make_user, senior, caregiver, senior_token):
    other_senior = make_user("senior", display_name="别人")
    link_relationship(app, senior, caregiver, status="accepted")
    link_relationship(app, other_senior, make_user("caregiver", display_name="别人的家属"), status="accepted")
    items = client.get("/api/v1/relationships", headers=headers(senior_token)).json()["items"]
    assert [item["senior_id"] for item in items] == [senior["id"]]


def test_authz_me_never_leaks_another_account(client, app, make_user, senior, senior_token):
    make_user("senior", display_name="别人")
    body = client.get("/api/v1/me", headers=headers(senior_token)).json()
    assert body["id"] == senior["id"]


def test_authz_revoked_link_reports_status(client, app, senior, caregiver, caregiver_token):
    link_relationship(app, senior, caregiver, status="revoked")
    body = client.get("/api/v1/me", headers=headers(caregiver_token)).json()
    assert body["relationship_status"] == "revoked"


def test_authz_audit_records_actor(client, app, senior, caregiver, senior_token):
    seed_consents(app, senior)
    from tests.helpers import insert_digest

    relationship = link_relationship(app, senior, caregiver, status="accepted")
    ctx = app.state.ctx
    client.delete(f"/api/v1/relationships/{relationship['id']}", headers=headers(senior_token))
    rows = ctx.db.query(
        "SELECT * FROM audit_events WHERE action = 'relationship_revoked'",
    )
    assert len(rows) == 1
    assert rows[0]["actor_user_id"] == senior["id"]
    assert rows[0]["target_type"] == "relationship"
    assert "王阿姨" not in (rows[0]["target_id"] or "")
