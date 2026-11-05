from __future__ import annotations


def test_health_is_public(client):
    response = client.get("/api/v1/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["version"]


def test_health_reports_offline_capabilities(client):
    body = client.get("/api/v1/health").json()
    # Guide §3.3: these must remain available without the internet.
    assert set(body["offline_capabilities"]) >= {
        "stop",
        "settings",
        "cached_activities",
        "system_calling",
    }


def test_unauthorized_error_shape(client):
    response = client.get("/api/v1/me")
    assert response.status_code == 401
    body = response.json()
    assert body["error"]["code"] == "unauthorized"
    assert body["error"]["message"]
