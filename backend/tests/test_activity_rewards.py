"""Encouragement rewards for activity answers (teacher feedback, 2026-11-10).

A correct answer earns one flower; a wrong one costs nothing. Nothing here is a
score, a level or a cognitive assessment — these tests pin the count only.
"""

from __future__ import annotations

from tests.helpers import headers


def _answer(client, token, *, activity_id: str, correct=None):
    body = {"activity_id": activity_id, "completed": True, "duration_seconds": 60}
    if correct is not None:
        body["correct"] = correct
    return client.post("/api/v1/activity-sessions", json=body, headers=headers(token))


def test_rewards_start_at_zero(client, senior, senior_token):
    response = client.get("/api/v1/rewards", headers=headers(senior_token))
    assert response.status_code == 200, response.text
    assert response.json() == {"flowers": 0}


def test_correct_answer_awards_one_flower(client, app, senior, senior_token):
    activity = app.state.ctx.activities.next_activity(int(senior["id"]))
    before = client.get("/api/v1/rewards", headers=headers(senior_token)).json()["flowers"]

    response = _answer(client, senior_token, activity_id=activity["id"], correct=True)

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["awarded"] is True
    assert body["flowers"] == before + 1
    assert client.get("/api/v1/rewards", headers=headers(senior_token)).json()["flowers"] == before + 1


def test_wrong_answer_awards_nothing_and_never_subtracts(client, app, senior, senior_token):
    activity = app.state.ctx.activities.next_activity(int(senior["id"]))
    _answer(client, senior_token, activity_id=activity["id"], correct=True)
    after_correct = client.get("/api/v1/rewards", headers=headers(senior_token)).json()["flowers"]

    response = _answer(client, senior_token, activity_id=activity["id"], correct=False)

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["awarded"] is False
    assert body["flowers"] == after_correct
    assert client.get("/api/v1/rewards", headers=headers(senior_token)).json()["flowers"] == after_correct


def test_memory_answer_without_correct_still_records(client, app, senior, senior_token):
    memory = app.state.ctx.activities.items_of_type("memory")[0]
    response = _answer(client, senior_token, activity_id=memory["id"])

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["recorded"] is True
    assert body["awarded"] is False
    assert body["flowers"] == 0


def test_rewards_are_per_senior(client, app, senior, senior_token, caregiver_token):
    activity = app.state.ctx.activities.next_activity(int(senior["id"]))
    _answer(client, senior_token, activity_id=activity["id"], correct=True)

    # A caregiver cannot read the senior's counter at all.
    response = client.get("/api/v1/rewards", headers=headers(caregiver_token))
    assert response.status_code == 403, response.text


def test_invalid_correct_value_is_rejected(client, senior, senior_token):
    response = client.post(
        "/api/v1/activity-sessions",
        json={
            "activity_id": "trivia-01",
            "completed": True,
            "duration_seconds": 60,
            "correct": "yes",
        },
        headers=headers(senior_token),
    )
    assert response.status_code == 422, response.text


def test_rewards_survive_restart(app, senior):
    engine = app.state.ctx.activities
    engine._award_flower(int(senior["id"]), "2026-11-10T00:00:00Z")
    engine._award_flower(int(senior["id"]), "2026-11-10T00:00:01Z")

    assert engine.flowers(int(senior["id"])) == 2
