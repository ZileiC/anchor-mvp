"""Activity content pack, rotation and session records (SPEC §6.5, surface ``s3_``)."""

from __future__ import annotations

import json
from collections import defaultdict

from app.activities.engine import CONTENT_PATH
from tests.helpers import headers, seed_consents

EXPECTED_TYPES = {"trivia", "story", "memory"}
TYPE_COUNTS = {"trivia": 5, "story": 4, "memory": 7}
TOTAL_ITEMS = sum(TYPE_COUNTS.values())
# Vocabulary that would turn a warm activity into a cognition test or baby talk.
FORBIDDEN_ZH = ("小朋友", "记性", "痴呆", "测试", "分数")


def _pack() -> list[dict]:
    return json.loads(CONTENT_PATH.read_text(encoding="utf-8"))["activities"]


def _grant(app, senior, *, observations=True):
    seed_consents(app, senior, record_observations=observations)


def test_s3_content_pack_is_complete():
    activities = _pack()
    assert len(activities) == TOTAL_ITEMS
    assert {item["type"] for item in activities} == EXPECTED_TYPES
    per_type = defaultdict(int)
    for item in activities:
        per_type[item["type"]] += 1
    assert dict(per_type) == TYPE_COUNTS

    ids = [item["id"] for item in activities]
    assert len(ids) == len(set(ids))
    for item in activities:
        assert item["id"].startswith(item["type"] + "-")
        assert item["title"] and item["prompt"]
        assert item["title_en"] and item["prompt_en"]
        assert item["minutes"] == 3


def test_s3_content_pack_matches_the_contract():
    """The app codes against this shape: answers are indices, memory has replies."""
    for item in _pack():
        kind = item["type"]
        option_count = len(item["options"])
        assert 3 <= option_count <= 4, item["id"]
        assert len(item["options_en"]) == option_count, item["id"]
        zh_strings = [item["title"], item["prompt"], *item["options"]]

        if kind in {"trivia", "story"}:
            answer = item["answer"]
            assert isinstance(answer, int) and not isinstance(answer, bool), item["id"]
            assert 0 <= answer < option_count, item["id"]
            assert item["explanation"].strip(), item["id"]
            assert item["explanation_en"].strip(), item["id"]
            hint = item["wrong_hint"]
            assert hint.strip(), item["id"]
            assert "错" not in hint, item["id"]
            assert item["wrong_hint_en"].strip(), item["id"]
            assert "replies" not in item, item["id"]
            zh_strings += [item["explanation"], hint]
            if kind == "story":
                story = item["story"]
                assert item["story_en"].strip(), item["id"]
                sentences = [part for part in story.split("。") if part.strip()]
                assert 2 <= len(sentences) <= 4, item["id"]
                zh_strings.append(story)
        else:
            replies = item["replies"]
            assert len(replies) == option_count, item["id"]
            assert len(item["replies_en"]) == len(replies), item["id"]
            assert len(set(replies)) == len(replies), item["id"]
            assert all(reply.strip() for reply in replies), item["id"]
            assert all(reply.strip() for reply in item["replies_en"]), item["id"]
            assert "answer" not in item, item["id"]
            assert "explanation" not in item, item["id"]
            zh_strings += replies

        for text in zh_strings:
            assert text.strip(), item["id"]
            for word in FORBIDDEN_ZH:
                assert word not in text, (item["id"], word)


def test_s3_list_activities_returns_items_and_rotation(client, app, senior, senior_token):
    _grant(app, senior)
    response = client.get("/api/v1/activities", headers=headers(senior_token))
    assert response.status_code == 200, response.text
    body = response.json()
    assert len(body["items"]) == TOTAL_ITEMS
    assert len(body["rotation"]) == len(body["items"])
    assert set(body["rotation"]) == {item["id"] for item in body["items"]}

    first = body["items"][0]
    assert first["id"] == "trivia-01"
    assert {
        "id",
        "type",
        "title",
        "prompt",
        "minutes",
        "options",
        "answer",
        "explanation",
        "wrong_hint",
    } <= set(first)
    assert isinstance(first["answer"], int)
    assert 0 <= first["answer"] < len(first["options"])

    memory = next(item for item in body["items"] if item["type"] == "memory")
    assert len(memory["replies"]) == len(memory["options"])
    assert "answer" not in memory
    story = next(item for item in body["items"] if item["type"] == "story")
    assert story["story"] and story["explanation"]


def test_s3_localise_passes_teaching_fields(app):
    engine = app.state.ctx.activities

    raw_trivia = engine.find("trivia-01")
    trivia = engine.localise(raw_trivia, "zh-CN")
    assert trivia["answer"] == raw_trivia["answer"]
    assert isinstance(trivia["answer"], int)
    assert trivia["explanation"] == raw_trivia["explanation"]
    assert trivia["wrong_hint"] == raw_trivia["wrong_hint"]
    assert trivia["options"] == raw_trivia["options"]

    trivia_en = engine.localise(raw_trivia, "en")
    assert trivia_en["answer"] == raw_trivia["answer"]
    assert trivia_en["options"] == raw_trivia["options_en"]
    assert trivia_en["explanation"] == raw_trivia["explanation_en"]
    assert trivia_en["wrong_hint"] == raw_trivia["wrong_hint_en"]

    raw_story = engine.find("story-01")
    story_en = engine.localise(raw_story, "en")
    assert story_en["story"] == raw_story["story_en"]
    assert story_en["prompt"] == raw_story["prompt_en"]
    assert story_en["explanation"] == raw_story["explanation_en"]

    raw_memory = engine.find("memory-01")
    memory = engine.localise(raw_memory, "zh-CN")
    assert memory["replies"] == raw_memory["replies"]
    assert memory["options"] == raw_memory["options"]
    assert "answer" not in memory
    assert "explanation" not in memory
    memory_en = engine.localise(raw_memory, "en")
    assert memory_en["replies"] == raw_memory["replies_en"]
    assert memory_en["options"] == raw_memory["options_en"]

    # Internal fields and raw translation keys never reach the app.
    for payload in (memory, trivia, story_en):
        assert not any(key.endswith("_en") for key in payload)
        assert "tags" not in payload


def test_s3_localised_titles(client, app, senior, senior_token):
    _grant(app, senior)
    raw = app.state.ctx.activities.all_items()
    body = client.get("/api/v1/activities", headers=headers(senior_token)).json()
    assert {item["id"]: item["title"] for item in body["items"]} == {
        item["id"]: item["title"] for item in raw
    }

    app.state.ctx.db.execute("UPDATE users SET locale = 'en' WHERE id = ?", (senior["id"],))
    body = client.get("/api/v1/activities", headers=headers(senior_token)).json()
    titles = {item["id"]: item["title"] for item in body["items"]}
    assert titles["memory-01"] == "The dish that was always on the table"
    assert titles["trivia-01"] == "A pan on fire"
    assert titles == {item["id"]: item["title_en"] for item in raw}
    assert not any(key.endswith("_en") for item in body["items"] for key in item)


def test_s3_rotation_never_repeats_until_all_shown(client, app, senior, senior_token):
    _grant(app, senior)
    engine = app.state.ctx.activities
    counts = {kind: len(engine.items_of_type(kind)) for kind in EXPECTED_TYPES}
    # Enough plays that every type completes a full pass and wraps once.
    plays = len(EXPECTED_TYPES) * (max(counts.values()) + 1)
    played: list[tuple[str, str]] = []
    for _ in range(plays):
        activity = engine.next_activity(int(senior["id"]))
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
        expected = [item["id"] for item in engine.items_of_type(activity_type)]
        assert len(expected) == counts[activity_type]
        # Every item of the type appears before anything of that type repeats...
        assert ids[: len(expected)] == expected, activity_type
        # ...then the type wraps to its first item and continues in order.
        assert ids == [expected[offset % len(expected)] for offset in range(len(ids))]


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
    family_ids = [
        item["id"]
        for item in app.state.ctx.activities.all_items()
        if "家庭" in item.get("tags", [])
    ]
    assert family_ids
    body = client.get("/api/v1/activities", headers=headers(senior_token)).json()
    assert [item["id"] for item in body["items"][: len(family_ids)]] == family_ids


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
