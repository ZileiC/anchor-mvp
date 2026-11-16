"""The senior chooses which of the two voices speaks (2026-11-16).

The provider exposes a female voice (``stella``) and a male one (``tide``), and
which sounds right is a matter of taste. The choice is stored as a *gender* so it
survives a provider change, and each adapter maps it onto its own voice name — the
edge fallback would otherwise be handed the word "male" as if it were a voice id.
"""

from __future__ import annotations

import pytest

from app.api.tts import DEFAULT_GENDER, voice_for_gender
from app.providers.tts import DEFAULT_VOICE, VOICE_MALE, EdgeTTS, resolve_voice
from app.providers.tts_deepseek import VOICE_FEMALE as DS_FEMALE
from app.providers.tts_deepseek import VOICE_MALE as DS_MALE
from tests.helpers import headers


def _patch(client, token, body):
    return client.patch("/api/v1/preferences", json=body, headers=headers(token))


def test_a_fresh_profile_hears_the_default_voice(client, senior_token):
    body = client.get("/api/v1/preferences", headers=headers(senior_token)).json()
    assert body["voice_gender"] is None
    assert voice_for_gender(body["voice_gender"]) == DEFAULT_GENDER


@pytest.mark.parametrize("gender", ["female", "male"])
def test_the_choice_is_stored_and_read_back(client, senior_token, gender):
    assert _patch(client, senior_token, {"voice_gender": gender}).status_code == 200
    body = client.get("/api/v1/preferences", headers=headers(senior_token)).json()
    assert body["voice_gender"] == gender


def test_an_unknown_voice_is_refused(client, senior_token):
    response = _patch(client, senior_token, {"voice_gender": "robot"})
    assert response.status_code == 422
    assert "female" in str(response.json()["error"]["message"])


def test_blank_or_null_returns_to_the_default(client, senior_token):
    _patch(client, senior_token, {"voice_gender": "male"})
    assert _patch(client, senior_token, {"voice_gender": ""}).json()["voice_gender"] is None
    _patch(client, senior_token, {"voice_gender": "male"})
    assert _patch(client, senior_token, {"voice_gender": None}).json()["voice_gender"] is None


def test_it_does_not_disturb_the_name_or_the_pace(client, senior_token):
    _patch(client, senior_token, {"assistant_name": "小安", "voice_pace": "normal"})
    body = _patch(client, senior_token, {"voice_gender": "male"}).json()
    assert body["assistant_name"] == "小安"
    assert body["voice_pace"] == "normal"
    assert body["voice_gender"] == "male"


@pytest.mark.parametrize(
    ("stored", "expected"),
    [(None, "female"), ("", "female"), ("female", "female"), ("male", "male"), ("MALE", "male")],
)
def test_voice_for_gender_never_fails(stored, expected):
    assert voice_for_gender(stored) == expected


def test_deepseek_maps_the_gender_onto_its_two_voices():
    from app.providers.tts_deepseek import resolve_voice as resolve_deepseek

    assert resolve_deepseek("male") == DS_MALE
    assert resolve_deepseek("female") == DS_FEMALE


def test_edge_maps_the_gender_onto_its_two_voices():
    assert resolve_voice("male") == VOICE_MALE
    assert resolve_voice("female") == DEFAULT_VOICE
    # DeepSeek's own words are accepted, because ANCHOR_TTS_VOICE has always taken
    # them and the same value flows through both adapters.
    assert resolve_voice("tide") == VOICE_MALE
    assert resolve_voice("stella") == DEFAULT_VOICE


def test_edge_keeps_a_fully_named_voice_untouched():
    assert resolve_voice("zh-CN-XiaoyiNeural") == "zh-CN-XiaoyiNeural"
    assert resolve_voice(None) is None
    assert resolve_voice("  ") is None


def test_the_fallback_speaks_the_same_gender():
    """DeepSeek down, senior asked for a man: the fallback must not be female."""
    spoken: list[tuple[str, str]] = []

    def fake_synth(text: str, voice: str, rate: str) -> bytes:
        spoken.append((voice, rate))
        return b"ID3fake-mp3"

    edge = EdgeTTS(synth=fake_synth)
    assert edge.synthesize("你好", voice="male")
    assert spoken[0][0] == VOICE_MALE
    assert edge.synthesize("你好", voice="female")
    assert spoken[1][0] == DEFAULT_VOICE


def test_the_route_asks_for_the_stored_voice(client, senior_token, app):
    """End to end on the route: the preference decides the voice argument."""
    seen: list[str] = []

    class Recorder:
        media_type = "audio/mpeg"
        spoken_with = "edge"

        def synthesize(self, text, voice=None, rate=None):
            seen.append(voice or "")
            return b"ID3fake-mp3"

    from app.api.tts import get_tts

    app.dependency_overrides[get_tts] = lambda: Recorder()
    try:
        _patch(client, senior_token, {"voice_gender": "male"})
        first = client.post(
            "/api/v1/tts", json={"text": "你好"}, headers=headers(senior_token)
        )
        assert first.status_code == 200, first.text
        _patch(client, senior_token, {"voice_gender": "female"})
        client.post("/api/v1/tts", json={"text": "你好"}, headers=headers(senior_token))
        # An explicit voice in the body still wins over the stored choice.
        client.post(
            "/api/v1/tts",
            json={"text": "你好", "voice": "tide"},
            headers=headers(senior_token),
        )
    finally:
        app.dependency_overrides.pop(get_tts, None)

    assert seen == ["male", "female", "tide"]
