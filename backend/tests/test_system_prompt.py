"""The conversation prompt: the senior's chosen name, and the eldercare skill.

Two defects this pins down (2026-11-16):

* the role line hardcoded the product's old placeholder name, so asking "你是谁"
  got "我是 Anchor" no matter what the older adult had called the companion;
* there was no eldercare guidance at all — the model answered with general chat
  behaviour instead of the craft this product is about.

The name must come from ``preferences.assistant_name`` (My choices), and the
guidance must actually reach the prompt in both languages.
"""

from __future__ import annotations

from app.conversation.eldercare_skill import SKILL_VERSION, guidance_lines
from app.conversation.prompt import DEFAULT_NAME, build_system_prompt, companion_name

SENIOR = {"id": 1, "locale": "zh-CN"}


def _prefs(**overrides):
    base = {
        "assistant_name": None,
        "short_replies": 1,
        "voice_pace": "slow",
    }
    base.update(overrides)
    return base


def test_a_new_profile_uses_the_product_name():
    prompt = build_system_prompt(SENIOR, _prefs(), [])
    assert prompt.startswith(f"你是{DEFAULT_NAME}")
    assert "Everhere" in prompt


def test_the_chosen_name_becomes_the_identity():
    prompt = build_system_prompt(SENIOR, _prefs(assistant_name="小安"), [])
    assert prompt.startswith("你是小安")
    assert "老人叫你「小安」" in prompt
    assert "Everhere" not in prompt


def test_the_model_is_told_to_answer_who_are_you_with_that_name():
    prompt = build_system_prompt(SENIOR, _prefs(assistant_name="老伴"), [])
    assert "被问到你是谁" in prompt
    assert "不要提别的产品名" in prompt
    assert "旧名字" in prompt


def test_a_blank_or_whitespace_name_falls_back():
    assert companion_name({"assistant_name": None}) == DEFAULT_NAME
    assert companion_name({"assistant_name": "   "}) == DEFAULT_NAME
    assert companion_name({}) == DEFAULT_NAME
    assert companion_name({"assistant_name": "  小安  "}) == "小安"


def test_the_old_placeholder_name_never_appears():
    for name in (None, "小安"):
        for locale in ("zh-CN", "en"):
            prompt = build_system_prompt({**SENIOR, "locale": locale}, _prefs(assistant_name=name), [])
            # The word may only appear inside the instruction not to use it.
            for line in prompt.splitlines():
                if "Anchor" in line:
                    assert "旧名字" in line or "older name" in line, line


def test_the_eldercare_guidance_reaches_the_prompt():
    zh = build_system_prompt(SENIOR, _prefs(), [])
    assert "[陪伴要点]" in zh
    for line in guidance_lines("zh-CN"):
        assert line in zh
    en = build_system_prompt({**SENIOR, "locale": "en"}, _prefs(), [])
    assert "[COMPANION_GUIDANCE]" in en
    for line in guidance_lines("en"):
        assert line in en


def test_the_guidance_says_what_matters_most():
    zh = "\n".join(guidance_lines("zh-CN"))
    assert "不争辩" in zh, "a mistaken memory must not be corrected"
    assert "不诊断、不评分、不谈病情" in zh
    assert "没听清" in zh, "never guess a transcript"
    assert "如实" in zh, "be honest about being a robot"
    assert "没法打电话" in zh, "never promise a call it cannot make"


def test_the_skill_is_versioned():
    assert SKILL_VERSION.count(".") >= 1


def test_reply_length_and_pace_still_come_from_preferences():
    prompt = build_system_prompt(SENIOR, _prefs(short_replies=False, voice_pace="normal"), [])
    assert "[简短] 0" in prompt
    assert "[语速] normal" in prompt


def test_approved_memories_are_included():
    memories = [{"fact": "女儿住杭州"}, {"fact": "爱看阳台的花"}]
    prompt = build_system_prompt(SENIOR, _prefs(assistant_name="小安"), memories)
    assert "[记忆]" in prompt
    assert "女儿住杭州" in prompt
    assert "爱看阳台的花" in prompt


def test_english_locale_uses_the_chosen_name_too():
    prompt = build_system_prompt(
        {**SENIOR, "locale": "en"}, _prefs(assistant_name="Little Ann"), []
    )
    assert prompt.startswith("You are Little Ann,")
    assert '"Little Ann"' in prompt
    assert "[LANG] en" in prompt
