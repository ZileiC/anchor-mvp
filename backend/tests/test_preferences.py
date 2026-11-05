"""Preferences read/patch validation (SPEC §6.1)."""

from __future__ import annotations

from tests.helpers import headers


def _patch(client, token, body):
    return client.patch("/api/v1/preferences", json=body, headers=headers(token))


def test_defaults_are_created_on_first_read(client, senior_token):
    response = client.get("/api/v1/preferences", headers=headers(senior_token))
    assert response.status_code == 200
    body = response.json()
    assert body["greeting_start"] == "09:00"
    assert body["greeting_end"] == "11:00"
    assert body["quiet_start"] == "21:00"
    assert body["quiet_end"] == "08:00"
    assert body["daily_cap"] == 1
    assert body["paused"] is False
    assert body["voice_pace"] == "slow"
    assert body["short_replies"] is True
    assert body["language"] == "zh-CN"
    assert body["observation_topics"] == [
        "participation",
        "activities",
        "mood",
        "meals",
        "wellbeing",
    ]


def test_patch_updates_window_and_pace(client, senior_token):
    response = _patch(
        client,
        senior_token,
        {
            "greeting_start": "10:30",
            "greeting_end": "12:00",
            "voice_pace": "normal",
            "short_replies": False,
            "language": "en",
        },
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["greeting_start"] == "10:30"
    assert body["greeting_end"] == "12:00"
    assert body["voice_pace"] == "normal"
    assert body["short_replies"] is False
    assert body["language"] == "en"


def test_quiet_hours_may_cross_midnight(client, senior_token):
    response = _patch(client, senior_token, {"quiet_start": "22:30", "quiet_end": "07:30"})
    assert response.status_code == 200
    assert response.json()["quiet_start"] == "22:30"


def test_invalid_time_rejected(client, senior_token):
    for bad in ("24:00", "9:00", "09:60", "0900", "abc"):
        response = _patch(client, senior_token, {"greeting_start": bad})
        assert response.status_code == 422, bad
        assert response.json()["error"]["code"] == "validation_error"


def test_daily_cap_must_be_zero_or_one(client, senior_token):
    assert _patch(client, senior_token, {"daily_cap": 0}).status_code == 200
    assert _patch(client, senior_token, {"daily_cap": 2}).status_code == 422


def test_unknown_field_rejected(client, senior_token):
    response = _patch(client, senior_token, {"theme": "dark"})
    assert response.status_code == 422
    assert "theme" in response.json()["error"]["message"]


def test_observation_topics_must_be_known(client, senior_token):
    assert (
        _patch(client, senior_token, {"observation_topics": ["mood", "meals"]}).status_code == 200
    )
    response = _patch(client, senior_token, {"observation_topics": ["mood", "sleep"]})
    assert response.status_code == 422


def test_interests_are_bounded(client, senior_token):
    assert _patch(client, senior_token, {"interests": ["唱戏", "养花"]}).status_code == 200
    assert client.get("/api/v1/preferences", headers=headers(senior_token)).json()[
        "interests"
    ] == ["唱戏", "养花"]
    assert (
        _patch(client, senior_token, {"interests": [f"爱好{i}" for i in range(11)]}).status_code
        == 422
    )


def test_snooze_roundtrip(client, senior_token):
    response = _patch(client, senior_token, {"snoozed_until": "2026-01-06T01:00:00Z"})
    assert response.status_code == 200
    assert response.json()["snoozed_until"] == "2026-01-06T01:00:00Z"
    cleared = _patch(client, senior_token, {"snoozed_until": None})
    assert cleared.status_code == 200
    assert cleared.json()["snoozed_until"] is None


def test_paused_flag(client, senior_token):
    assert _patch(client, senior_token, {"paused": True}).json()["paused"] is True
    assert _patch(client, senior_token, {"paused": False}).json()["paused"] is False


def test_designated_device(client, senior_token):
    response = _patch(client, senior_token, {"designated_device_id": "tablet-kitchen"})
    assert response.status_code == 200
    assert response.json()["designated_device_id"] == "tablet-kitchen"


def test_caregiver_cannot_read_or_patch_preferences(client, caregiver_token):
    assert client.get("/api/v1/preferences", headers=headers(caregiver_token)).status_code == 403
    response = _patch(client, caregiver_token, {"paused": True})
    assert response.status_code == 403
    assert response.json()["error"]["code"] == "forbidden"


def test_patch_requires_token(client):
    assert client.patch("/api/v1/preferences", json={"paused": True}).status_code == 401
