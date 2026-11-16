"""The older adult may name the companion (2026-11-16).

The chat labels the assistant's lines with a fixed word. Letting the older adult
type the name they want is a small thing that makes the appliance feel like
theirs — and it is their decision alone: the family phone cannot change it, and a
blank value goes back to the product default instead of leaving an empty label.
"""

from __future__ import annotations

import pytest

from tests.helpers import headers


def _get(client, token):
    return client.get("/api/v1/preferences", headers=headers(token))


def _patch(client, token, body):
    return client.patch("/api/v1/preferences", json=body, headers=headers(token))


def test_a_fresh_profile_has_no_assistant_name(client, senior_token):
    body = _get(client, senior_token).json()
    assert body["assistant_name"] is None


def test_the_name_is_stored_and_returned(client, senior_token):
    response = _patch(client, senior_token, {"assistant_name": "小安"})
    assert response.status_code == 200, response.text
    assert response.json()["assistant_name"] == "小安"
    assert _get(client, senior_token).json()["assistant_name"] == "小安"


def test_surrounding_and_repeated_whitespace_is_collapsed(client, senior_token):
    body = _patch(
        client, senior_token, {"assistant_name": "  阿   姨  "}
    ).json()
    assert body["assistant_name"] == "阿 姨"


def test_a_blank_name_goes_back_to_the_default(client, senior_token):
    _patch(client, senior_token, {"assistant_name": "小安"})
    body = _patch(client, senior_token, {"assistant_name": "   "}).json()
    assert body["assistant_name"] is None
    assert _get(client, senior_token).json()["assistant_name"] is None


def test_null_clears_it(client, senior_token):
    _patch(client, senior_token, {"assistant_name": "奶奶"})
    body = _patch(client, senior_token, {"assistant_name": None}).json()
    assert body["assistant_name"] is None


def test_a_too_long_name_is_refused(client, senior_token):
    response = _patch(client, senior_token, {"assistant_name": "十三个字符的名字太长了不行"})
    assert response.status_code == 422
    assert "12" in str(response.json()["error"]["message"])


@pytest.mark.parametrize("value", [5, True, ["小安"], {"name": "小安"}])
def test_a_non_string_is_refused(client, senior_token, value):
    response = _patch(client, senior_token, {"assistant_name": value})
    assert response.status_code == 422


def test_control_characters_are_refused(client, senior_token):
    response = _patch(client, senior_token, {"assistant_name": "小\u0007安"})
    assert response.status_code == 422


def test_the_twelve_character_ceiling_is_inclusive(client, senior_token):
    twelve = "一二三四五六七八九十一二"
    assert len(twelve) == 12
    assert _patch(client, senior_token, {"assistant_name": twelve}).status_code == 200


def test_a_caregiver_cannot_set_it(client, caregiver_token):
    response = _patch(client, caregiver_token, {"assistant_name": "小安"})
    assert response.status_code == 403


def test_it_does_not_disturb_other_preferences(client, senior_token):
    _patch(client, senior_token, {"voice_pace": "normal", "assistant_name": "小安"})
    body = _patch(client, senior_token, {"assistant_name": None}).json()
    assert body["voice_pace"] == "normal"
