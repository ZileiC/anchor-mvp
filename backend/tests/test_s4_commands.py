"""One-step command routing (SPEC §6.3 step 4, surface ``s4_``)."""

from __future__ import annotations

import pytest

from app.conversation.commands import call_target, match_contact, route


@pytest.mark.parametrize(
    "utterance",
    ["停", "停止", "别说了", "先别说了", "stop", "quiet", "安静一点"],
)
def test_s4_stop_words(utterance):
    assert route(utterance) == {"type": "stop"}


@pytest.mark.parametrize("utterance", ["再说一遍", "重复", "repeat", "再说一次"])
def test_s4_repeat_words(utterance):
    assert route(utterance) == {"type": "repeat"}


@pytest.mark.parametrize("utterance", ["玩", "游戏", "下棋", "play"])
def test_s4_play_words(utterance):
    assert route(utterance) == {"type": "play"}


@pytest.mark.parametrize(
    "utterance,expected",
    [
        ("给儿子打电话", "儿子"),
        ("给小李打电话", "小李"),
        ("打电话给儿子", "儿子"),
        ("call 小李", "小李"),
        ("call", None),
        ("打个电话", None),
    ],
)
def test_s4_call_target_extraction(utterance, expected):
    assert call_target(utterance) == expected
    if expected is not None or "call" in utterance:
        assert route(utterance) == {"type": "call", "target": expected}


@pytest.mark.parametrize(
    "utterance",
    ["今天天气不错", "我想喝点水", "昨天睡得还行", "下午想出去走走"],
)
def test_s4_ordinary_speech_is_not_a_command(utterance):
    assert route(utterance) is None


def test_s4_stop_wins_over_other_words():
    assert route("别玩了，停下来") == {"type": "stop"}


def test_s4_contact_resolution_exact_then_contains():
    contacts = [
        {"id": 1, "label": "儿子", "phone": "123"},
        {"id": 2, "label": "小李", "phone": "456"},
    ]
    assert match_contact(contacts, "儿子")["id"] == 1
    assert match_contact(contacts, "小李")["id"] == 2
    assert match_contact(contacts, "女儿") is None
    assert match_contact(contacts, None) is None
    assert match_contact([], "儿子") is None


def test_s4_contact_resolution_is_case_insensitive():
    contacts = [{"id": 1, "label": "Li", "phone": "1"}]
    assert match_contact(contacts, "li")["id"] == 1
