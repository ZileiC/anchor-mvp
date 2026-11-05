"""Provider adapters: deterministic fakes and HTTP error mapping (SPEC §2)."""

from __future__ import annotations

import httpx
import pytest

from app.config import Settings
from app.errors import AppError
from app.providers import build_providers
from app.providers.asr_fake import FakeASR
from app.providers.asr_http import HttpASR
from app.providers.llm_http import HttpLLM
from app.providers.llm_rule import RuleLLM, language_of, memory_facts

SYSTEM_ZH = "\n".join(
    [
        "你是 Anchor。",
        "[语言] zh-CN",
        "[简短] 1",
        "[记忆]",
        "- 养过一只叫小黑的猫",
        "- 喜欢听京剧",
        "[规则] 只问一个问题。",
    ]
)


def test_rule_llm_replies_deterministically():
    llm = RuleLLM()
    first = llm.reply(SYSTEM_ZH, [{"role": "user", "content": "今天天气不错"}])
    second = RuleLLM().reply(SYSTEM_ZH, [{"role": "user", "content": "今天天气不错"}])
    assert first == second
    assert isinstance(first, str) and first


def test_rule_llm_echoes_best_memory():
    llm = RuleLLM()
    reply = llm.reply(SYSTEM_ZH, [{"role": "user", "content": "小黑今天怎么样"}])
    assert "养过一只叫小黑的猫" in reply


def test_rule_llm_without_memory_block():
    llm = RuleLLM()
    reply = llm.reply("[语言] zh-CN\n[规则] 只问一个问题。", [{"role": "user", "content": "小黑今天怎么样"}])
    assert "小黑" not in reply


def test_rule_llm_english():
    system = "[LANG] en\n[SHORT] 1\n[RULES] short"
    reply = RuleLLM().reply(system, [{"role": "user", "content": "I had lunch today"}])
    assert isinstance(reply, str) and reply
    assert any(word in reply.lower() for word in ("meal", "eat", "food", "dish"))


def test_memory_facts_parser():
    assert memory_facts(SYSTEM_ZH) == ["养过一只叫小黑的猫", "喜欢听京剧"]
    assert memory_facts("no block here") == []


def test_language_detection():
    assert language_of(SYSTEM_ZH) == "zh-CN"
    assert language_of("[语言] en\n") == "en"
    assert language_of("[LANG] en\n") == "en"


def test_fake_asr_is_deterministic():
    asr = FakeASR("我今天吃过饭了")
    assert asr.transcribe(b"123", "audio/wav") == "我今天吃过饭了"
    assert asr.calls == [(3, "audio/wav")]
    asr.set_transcript("好的")
    assert asr.transcribe(b"1") == "好的"


def test_http_llm_parses_openai_response():
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path.endswith("/chat/completions")
        assert request.headers["authorization"] == "Bearer key-123"
        return httpx.Response(
            200, json={"choices": [{"message": {"content": " 你好呀 "}}]}
        )

    llm = HttpLLM("https://llm.example/api", api_key="key-123", transport=httpx.MockTransport(handler))
    assert llm.reply("sys", [{"role": "user", "content": "hi"}]) == "你好呀"


def test_http_llm_server_error_maps_to_provider_unavailable():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(503, json={"error": "down"})

    llm = HttpLLM("https://llm.example", transport=httpx.MockTransport(handler))
    with pytest.raises(AppError) as excinfo:
        llm.reply("sys", [{"role": "user", "content": "hi"}])
    assert excinfo.value.code == "provider_unavailable"
    assert excinfo.value.status == 503
    assert excinfo.value.extra["recovery"] == ["retry", "type_instead"]


def test_http_llm_network_error_maps_to_provider_unavailable():
    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("no route", request=request)

    llm = HttpLLM("https://llm.example", transport=httpx.MockTransport(handler))
    with pytest.raises(AppError) as excinfo:
        llm.reply("sys", [{"role": "user", "content": "hi"}])
    assert excinfo.value.code == "provider_unavailable"


def test_http_llm_empty_content_is_unavailable():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"choices": [{"message": {"content": "   "}}]})

    llm = HttpLLM("https://llm.example", transport=httpx.MockTransport(handler))
    with pytest.raises(AppError):
        llm.reply("sys", [])


def test_http_asr_parses_response():
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path.endswith("/audio/transcriptions")
        return httpx.Response(200, json={"text": "我想喝水"})

    asr = HttpASR("https://asr.example/v1", transport=httpx.MockTransport(handler))
    assert asr.transcribe(b"abc", "audio/wav") == "我想喝水"


def test_http_asr_error_maps_to_provider_unavailable():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(500)

    asr = HttpASR("https://asr.example", transport=httpx.MockTransport(handler))
    with pytest.raises(AppError) as excinfo:
        asr.transcribe(b"abc")
    assert excinfo.value.code == "provider_unavailable"
    assert excinfo.value.extra["recovery"] == ["retry", "type_instead"]


def test_build_providers_defaults_to_offline_adapters(tmp_path):
    from app.clock import FakeClock
    from app.db import Database

    db = Database(tmp_path / "a.db")
    db.migrate()
    providers = build_providers(Settings(env="test", db_path=str(tmp_path / "a.db")), FakeClock(), db)
    assert isinstance(providers["asr"], FakeASR)
    assert isinstance(providers["llm"], RuleLLM)
    assert providers["notifier"] is not None
    db.close()


def test_build_providers_http_when_configured(tmp_path):
    from app.clock import FakeClock
    from app.db import Database

    db = Database(tmp_path / "a.db")
    db.migrate()
    settings = Settings(
        env="test",
        db_path=str(tmp_path / "a.db"),
        asr_provider="http",
        asr_url="https://asr.example",
        llm_provider="http",
        llm_url="https://llm.example",
    )
    providers = build_providers(settings, FakeClock(), db)
    assert isinstance(providers["asr"], HttpASR)
    assert isinstance(providers["llm"], HttpLLM)
    db.close()
