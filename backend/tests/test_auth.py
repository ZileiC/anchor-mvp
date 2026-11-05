from __future__ import annotations

from app.auth import issue_token


def test_dev_login_and_me(client, senior):
    body = client.post("/api/v1/dev/login", json={"user_id": senior["id"]}).json()
    assert body["token_type"] == "bearer"
    token = body["access_token"]

    response = client.get("/api/v1/me", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
    me = response.json()
    assert me["role"] == "senior"
    assert me["senior_id"] == senior["id"]
    assert me["display_name"]


def test_caregiver_me_reports_linked_senior(client, app, caregiver, caregiver_token, linked):
    response = client.get(
        "/api/v1/me",
        headers={"Authorization": f"Bearer {caregiver_token}"},
    )
    assert response.status_code == 200
    me = response.json()
    assert me["role"] == "caregiver"
    assert me["senior_id"] == linked["senior_id"]
    assert me["relationship_status"] == "accepted"


def test_malformed_token_rejected(client):
    response = client.get("/api/v1/me", headers={"Authorization": "Bearer not-a-token"})
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "unauthorized"


def test_token_expiry(app, client, senior, senior_token, clock):
    clock.advance(days=2)
    response = client.get("/api/v1/me", headers={"Authorization": f"Bearer {senior_token}"})
    assert response.status_code == 401


def test_dev_login_disabled_in_production(client_production):
    response = client_production.post("/api/v1/dev/login", json={"user_id": 1})
    assert response.status_code == 404
    assert response.json()["error"]["code"] == "not_found"


def test_token_role_mismatch_rejected(app, senior, client):
    forged, _ = issue_token(app.state.ctx.settings, senior["id"], "caregiver", app.state.ctx.clock)
    response = client.get("/api/v1/me", headers={"Authorization": f"Bearer {forged}"})
    assert response.status_code == 401


def test_validation_error_shape(client):
    response = client.post("/api/v1/dev/login", json={"user_id": "not-an-int"})
    assert response.status_code == 422
    body = response.json()
    assert body["error"]["code"] == "validation_error"
