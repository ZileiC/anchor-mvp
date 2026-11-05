"""Activity content pack, rotation and session records (SPEC §6.5, surface ``s3_``)."""

from __future__ import annotations

from collections import defaultdict

from app.activities.engine import CONTENT_PATH
from tests.helpers import headers, seed_consents

EXPECTED_TYPES = {"trivia", "story", "memory"}


def _grant(app, senior, *, observations=True):
    seed_consents(app, senior, record_observations=observations)


def test_s3_content_pack_is_complete():
    import json

    payload = json.loads(CONTENT_PATH.read_text(encoding="utf-8"))
    activities = payload["activities"]
    assert len(activities) >= 18
    assert {item["type"] for item in activities} == EXPECTED_TYPES
    ids = [item["id"] for item in activities]
    assert len(ids) == len(set(ids))
    for item in activities:
        assert item["title"] and item["prompt"]
        assert item["minutes"] >= 1
        assert item["title_en"] and item["prompt_en"]
    per_type = defaultdict(int)
    for item in activities:
        per_type[item["type"]] += 1
    assert all(count >= 6 for count in per_type.values())


def test_s3_list_activities_returns_items_and_rotation(client, app, senior, senior_token):
    _grant(app, senior)
    response = client.get("/api/v1/activities", headers=headers(senior_token))
    assert response.status_code == 200, response.text
    body = response.json()
    assert len(body["items"]) >= 18
    assert len(body["rotation"]) == len(body["items"])
    assert len(set(body["rotation"])) == len(body["rotation"])
    first = body["items"][0]
    assert {"id", "type", "title", "prompt", "minutes"} <= set(first)


def test_s3_localised_titles(client, app, senior, senior_token):
    _grant(app, senior)
    app.state.ctx.db.execute("UPDATE users SET locale = 'en' WHERE id = ?", (senior["id"],))
    body = client.get("/api/v1/activities", headers=headers(senior_token)).json()
    assert all(item["title"] for item in body["items"])
    titles = {item["id"]: item["title"] for item in body["items"]}
    assert titles["memory-01"] == "Remember three things"


def test_s3_rotation_never_repeats_until_all_shown(client, app, senior, senior_token):
    _grant(app, senior)
    played: list[tuple[str, str]] = []
    for _ in range(18):
        activity = app.state.ctx.activities.next_activity(int(senior["id"]))
        played.append((activity["type"], activity["id"]))
        response = client.post(
            "/api/v1/activity-sessions",
            json={"activity_id": activity["id"], "completed": True, "duration_seconds": 120},
            headers=headers(senior_token),
        )
        assert response.status_code == 200, response.text

    by_type: dict[str, list[str]] = defaultdict(list)
    for activity_type, activity_id in played:
        by_type[activity_type].append(activity_id)
    assert set(by_type) == EXPECTED_TYPES
    for activity_type, ids in by_type.items():
        assert len(ids) == len(set(ids)), activity_type
        expected = {item["id"] for item in app.state.ctx.activities.items_of_type(activity_type)}
        assert set(ids) == expected

    # The nineteenth play wraps around instead of repeating early.
    first_again = app.state.ctx.activities.next_activity(int(senior["id"]))
    assert first_again["id"] == played[0][1]


def test_s3_rotation_survives_restart(app, senior, settings, clock):
    _grant(app, senior)
    engine = app.state.ctx.activities
    first = engine.next_activity(int(senior["id"]))
    engine.record_session(int(senior["id"]), first["id"], True, 60)
    expected_next = engine.next_activity(int(senior["id"]))["id"]

    from app.main import create_app

    restarted = create_app(settings, clock)
    try:
        after = restarted.state.ctx.activities.next_activity(int(senior["id"]))
        assert after["id"] == expected_next
    finally:
        restarted.state.ctx.close()


def test_s3_activity_session_records_observation(client, app, senior, senior_token):
    _grant(app, senior)
    response = client.post(
        "/api/v1/activity-sessions",
        json={"activity_id": "trivia-01", "completed": True, "duration_seconds": 90},
        headers=headers(senior_token),
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["recorded"] is True
    assert body["observation_recorded"] is True
    assert body["next_activity_id"]
    observations = app.state.ctx.db.query("SELECT * FROM observations")
    assert len(observations) == 1
    assert observations[0]["topic"] == "activities"
    assert observations[0]["source_ref"] == "trivia-01"


def test_s3_activity_session_without_consent_records_nothing(client, app, senior, senior_token):
    _grant(app, senior, observations=False)
    body = client.post(
        "/api/v1/activity-sessions",
        json={"activity_id": "trivia-02", "completed": False, "duration_seconds": 30},
        headers=headers(senior_token),
    ).json()
    assert body["observation_recorded"] is False
    assert app.state.ctx.db.query("SELECT * FROM observations") == []


def test_s3_unknown_activity_is_404(client, app, senior, senior_token):
    _grant(app, senior)
    response = client.post(
        "/api/v1/activity-sessions",
        json={"activity_id": "nope-99", "completed": True, "duration_seconds": 30},
        headers=headers(senior_token),
    )
    assert response.status_code == 404


def test_s3_invalid_session_payload(client, app, senior, senior_token):
    _grant(app, senior)
    for body in (
        {"activity_id": "trivia-01", "completed": "maybe", "duration_seconds": 30},
        {"activity_id": "trivia-01", "completed": True, "duration_seconds": -1},
        {"activity_id": "trivia-01", "completed": True, "duration_seconds": 999999},
    ):
        response = client.post(
            "/api/v1/activity-sessions", json=body, headers=headers(senior_token)
        )
        assert response.status_code == 422, body


def test_s3_interests_are_prioritised(client, app, senior, senior_token):
    _grant(app, senior)
    app.state.ctx.preferences.patch(int(senior["id"]), {"interests": ["家庭"]})
    body = client.get("/api/v1/activities", headers=headers(senior_token)).json()
    assert body["items"][0]["id"] in {"story-01", "memory-06"}


def test_s3_caregiver_cannot_read_activities(client, app, senior, caregiver, senior_token, caregiver_token):
    from tests.helpers import link_relationship

    _grant(app, senior)
    link_relationship(app, senior, caregiver, status="accepted")
    assert client.get("/api/v1/activities", headers=headers(caregiver_token)).status_code == 403
    assert (
        client.post(
            "/api/v1/activity-sessions",
            json={"activity_id": "trivia-01", "completed": True, "duration_seconds": 10},
            headers=headers(caregiver_token),
        ).status_code
        == 403
    )
