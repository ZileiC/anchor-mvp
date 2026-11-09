"""Settings load from ``ANCHOR_*`` environment (SPEC §2)."""

from __future__ import annotations

import pytest

from app.config import DEFAULT_DEV_SECRET, Settings


def test_defaults_are_dev_safe(monkeypatch):
    for key in list(__import__("os").environ):
        if key.startswith("ANCHOR_"):
            monkeypatch.delenv(key, raising=False)
    settings = Settings.from_env()
    assert settings.env == "dev"
    assert settings.secret == DEFAULT_DEV_SECRET
    assert settings.db_path.endswith("anchor.db")
    assert settings.timezone == "Asia/Shanghai"
    assert settings.asr_provider == "none"  # honest "not configured", never FakeASR
    assert settings.llm_provider == "rule"
    assert settings.token_ttl_seconds == 86400
    assert settings.job_lease_seconds == 120
    assert settings.is_dev is True


def test_env_overrides(monkeypatch):
    monkeypatch.setenv("ANCHOR_ENV", "test")
    monkeypatch.setenv("ANCHOR_SECRET", "unit-test-secret")
    monkeypatch.setenv("ANCHOR_DB_PATH", ":memory:")
    monkeypatch.setenv("ANCHOR_TOKEN_TTL_SECONDS", "60")
    settings = Settings.from_env()
    assert settings.env == "test"
    assert settings.secret == "unit-test-secret"
    assert settings.db_path == ":memory:"
    assert settings.token_ttl_seconds == 60


def test_production_rejects_default_secret():
    with pytest.raises(ValueError):
        Settings(env="production", secret=DEFAULT_DEV_SECRET)


def test_production_accepts_custom_secret(tmp_path):
    settings = Settings(
        env="production",
        secret="real-secret-value-123",
        db_path=str(tmp_path / "a.db"),
    )
    assert settings.is_dev is False


def test_invalid_env_rejected():
    with pytest.raises(ValueError):
        Settings(env="staging")


def test_invalid_provider_rejected():
    with pytest.raises(ValueError):
        Settings(llm_provider="magic")


def test_honest_provider_modes_are_accepted():
    assert Settings(asr_provider="none").asr_provider == "none"
    assert Settings(asr_provider="auto").asr_provider == "auto"
    assert Settings(asr_provider="fake").asr_provider == "fake"
    assert Settings(llm_provider="none").llm_provider == "none"
    assert Settings(llm_provider="rule").llm_provider == "rule"


def test_http_provider_requires_url_in_production():
    with pytest.raises(ValueError):
        Settings(env="production", secret="s3cret-value", llm_provider="http")
