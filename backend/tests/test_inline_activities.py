"""Activities offered inside a normal conversation (product decision 2026-11-10).

Play is no longer a separate world: a plain chat turn may carry one activity in
its response, chosen from the same persisted rotation as the Play screen. These
tests pin the offer rules (three turns of history, two quiet turns after a card,
never twice in one session), the response shape, the localised bridge sentence,
and the answering path — the choice goes back as an ordinary chat turn while the
result is recorded through the existing ``POST /activity-sessions`` endpoint.
"""

from __future__ import annotations

from app.activities.engine import OFFER_GAP_TURNS, OFFER_MIN_TURNS
from tests.helpers import RecordingLLM, headers, seed_consents


def _grant(app, senior) -> None:
    seed_consents(app, senior, cloud_processing=True, record_observations=True)


def _open(client, token) -> dict:
    response = client.post(
        "/api/v1/sessions", json={"origin": "voluntary"}, headers=headers(token)
    )
    assert response.status_code == 200, response.text
    return response.json()


def _chat(client, token, session_id: str, text: str) -> dict:
    response = client.post(
        f"/api/v1/sessions/{session_id}/turns",
        json={"text": text},
        headers=headers(token),
    )
    assert response.status_code == 200, response.text
    return response.json()


def _three_turns(client, token, session_id: str) -> list[dict]:
    return [
        _chat(client, token, session_id, "今天早上吃了面条"),
        _chat(client, token, session_id, "上午在楼下坐了会儿"),
        _chat(client, token, session_id, "中午有点困"),
    ]


def test_no_activity_before_three_turns_and_one_on_the_third(
    client, app, senior, senior_token
):
    _grant(app, senior)
    session = _open(client, senior_token)
    bodies = _three_turns(client, senior_token, session["session_id"])

    assert "activity" not in bodies[0]
    assert "activity" not in bodies[1]
    offer = bodies[2]["activity"]
    assert offer, "the third chat turn should carry an activity"

    assert offer["activity_id"].startswith(("trivia-", "story-", "memory-"))
    item = offer["item"]
    assert item["id"] == offer["activity_id"]
    assert item["prompt"] and item["title"] and item["options"]
    # The same localisation the Play screen gets: internal fields never leak.
    assert not any(key.endswith("_en") for key in item)
    assert "tags" not in item


def test_reply_text_introduces_the_card_without_hard_coding_the_question(
    client, app, senior, senior_token
):
    _grant(app, senior)
    session = _open(client, senior_token)
    bodies = _three_turns(client, senior_token, session["session_id"])
    offer = bodies[2]["activity"]
    reply = bodies[2]["reply_text"]

    assert reply.endswith(offer["intro"])
    assert offer["intro"] == app.state.ctx.activities.intro_for(
        offer["item"]["type"], "zh-CN"
    )
    # The question lives only in the structured field, never in the sentence.
    assert offer["item"]["prompt"] not in reply
    assert offer["item"]["prompt"] not in offer["intro"]
    # The caption stream carries the same sentence the card follows.
    assert bodies[2]["captions"][-1]["text"] == reply


def test_offers_keep_two_quiet_turns_between_cards(client, app, senior, senior_token):
    _grant(app, senior)
    session = _open(client, senior_token)
    offered_on: list[int] = []
    for number in range(1, 8):
        body = _chat(client, senior_token, session["session_id"], f"第{number}句话")
        if "activity" in body:
            offered_on.append(number)

    assert offered_on, "some turn must carry a card"
    for previous, following in zip(offered_on, offered_on[1:]):
        assert following - previous > OFFER_GAP_TURNS, offered_on
    # The first card comes no earlier than the configured warm-up.
    assert offered_on[0] >= OFFER_MIN_TURNS


def test_an_item_is_never_offered_twice_in_one_session(client, app, senior, senior_token):
    _grant(app, senior)
    session = _open(client, senior_token)
    offered: list[str] = []
    for number in range(1, 16):
        body = _chat(client, senior_token, session["session_id"], f"第{number}句话")
        if "activity" in body:
            offered.append(body["activity"]["activity_id"])

    assert len(offered) >= 4, offered
    assert len(offered) == len(set(offered)), offered


def test_every_item_is_offered_once_then_the_cards_stop(app, senior):
    """The engine itself stops after the whole rotation was offered."""
    _grant(app, senior)
    engine = app.state.ctx.activities
    senior_id = int(senior["id"])
    session_id = "rotation-exhaustion-session"
    app.state.ctx.db.execute(
        "INSERT INTO sessions(id, senior_id, origin, state, cancellation_token, started_at) "
        "VALUES (?,?,?,?,?,?)",
        (session_id, senior_id, "voluntary", "active", "token", "2026-01-05T01:00:00Z"),
    )
    offered: list[str] = []
    for number in range(1, 80):
        offer = engine.offer_for_turn(senior_id, session_id, number)
        if offer is None:
            continue
        offered.append(offer["activity_id"])

    assert set(offered) == {item["id"] for item in engine.all_items()}
    assert len(offered) == len(engine.all_items())
    # Nothing is left, so a later eligible turn has nothing to hand out.
    assert engine.offer_for_turn(senior_id, session_id, 80) is None


def test_an_offer_does_not_advance_the_rotation(client, app, senior, senior_token):
    _grant(app, senior)
    engine = app.state.ctx.activities
    before = engine.next_activity(int(senior["id"]))["id"]
    session = _open(client, senior_token)
    body = _three_turns(client, senior_token, session["session_id"])[2]
    assert body["activity"]["activity_id"] == before

    # Same rotation head: offering is not playing, so the pack is not skipped.
    assert engine.next_activity(int(senior["id"]))["id"] == before


def test_answering_uses_the_existing_activity_endpoint_and_a_normal_chat_turn(
    client, app, senior, senior_token
):
    _grant(app, senior)
    session = _open(client, senior_token)
    offer = _three_turns(client, senior_token, session["session_id"])[2]["activity"]
    item = app.state.ctx.activities.find(offer["activity_id"])
    chosen = item["options"][0]

    recorded = client.post(
        "/api/v1/activity-sessions",
        json={"activity_id": offer["activity_id"], "completed": True, "duration_seconds": 41},
        headers=headers(senior_token),
    )
    assert recorded.status_code == 200, recorded.text
    assert recorded.json()["recorded"] is True
    assert recorded.json()["next_activity_id"] != offer["activity_id"]

    observations = app.state.ctx.db.query(
        "SELECT * FROM observations WHERE topic = 'activities'"
    )
    assert [row["source_ref"] for row in observations] == [offer["activity_id"]]

    answer = _chat(client, senior_token, session["session_id"], f"我选了：{chosen}")
    assert answer["intent"] == "chat"
    assert answer["transcript"] == f"我选了：{chosen}"
    # The gap rule keeps the answer turn clear: no second card right away.
    assert "activity" not in answer


def test_intro_is_localised(client, app, senior, senior_token):
    _grant(app, senior)
    app.state.ctx.db.execute("UPDATE users SET locale = 'en' WHERE id = ?", (senior["id"],))
    session = _open(client, senior_token)
    bodies = _three_turns(client, senior_token, session["session_id"])
    offer = bodies[2]["activity"]
    assert offer["intro"].startswith("Oh — ")
    assert bodies[2]["reply_text"].endswith(offer["intro"])
    assert offer["item"]["prompt"] == app.state.ctx.activities.find(
        offer["activity_id"]
    )["prompt_en"]


def test_command_turns_never_carry_a_card(client, app, senior, senior_token):
    _grant(app, senior)
    session = _open(client, senior_token)
    _three_turns(client, senior_token, session["session_id"])
    for utterance in ("再说一遍", "玩个游戏吧"):
        body = _chat(client, senior_token, session["session_id"], utterance)
        assert "activity" not in body, utterance


def test_a_new_session_starts_with_a_clean_slate(client, app, senior, senior_token):
    _grant(app, senior)
    first = _open(client, senior_token)
    _three_turns(client, senior_token, first["session_id"])
    client.post(f"/api/v1/sessions/{first['session_id']}/stop", headers=headers(senior_token))

    second = _open(client, senior_token)
    bodies = _three_turns(client, senior_token, second["session_id"])
    assert "activity" in bodies[2], "offers are tracked per session, not globally"


def test_deleting_data_removes_offer_rows(client, app, senior, senior_token):
    _grant(app, senior)
    session = _open(client, senior_token)
    _three_turns(client, senior_token, session["session_id"])
    assert app.state.ctx.db.query("SELECT * FROM activity_offers")

    response = client.request(
        "DELETE", "/api/v1/data", json={"confirm": True}, headers=headers(senior_token)
    )
    assert response.status_code == 200, response.text
    assert app.state.ctx.db.query("SELECT * FROM activity_offers") == []


def test_the_model_still_answers_the_chat_part(client, app, senior, senior_token, use_providers):
    """The card is attached to a real model reply, not instead of it."""
    _grant(app, senior)
    recorder = RecordingLLM("好呀，慢慢说。")
    use_providers(llm=recorder)
    session = _open(client, senior_token)
    body = _three_turns(client, senior_token, session["session_id"])[2]

    assert len(recorder.calls) == 3
    assert body["reply_text"].startswith("好呀，慢慢说。")
    assert body["reply_text"].endswith(body["activity"]["intro"])
