"""Application settings, loaded from ANCHOR_* environment variables (SPEC §2)."""
from __future__ import annotations

import os
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Any, Optional

DEFAULT_DEV_SECRET = "dev-only-secret-change-me"

ENVS = ("dev", "test", "production")
ASR_PROVIDERS = ("fake", "http")
LLM_PROVIDERS = ("rule", "http")

BACKEND_DIR = Path(__file__).resolve().parent.parent


def _env(name: str, default: str) -> str:
    value = os.environ.get(name)
    return value if value not in (None, "") else default


def _env_int(name: str, default: int) -> int:
    raw = os.environ.get(name)
    try:
        return int(raw) if raw else default
    except ValueError:
        return default


@dataclass(frozen=True)
class Settings:
    env: str = "dev"
    secret: str = DEFAULT_DEV_SECRET
    db_path: str = str(BACKEND_DIR / "data" / "anchor.db")
    timezone: str = "Asia/Shanghai"
    token_ttl_seconds: int = 86400
    worker_interval_seconds: int = 60
    job_lease_seconds: int = 120
    asr_provider: str = "fake"
    asr_url: Optional[str] = None
    asr_api_key: Optional[str] = None
    asr_model: str = "whisper-1"
    llm_provider: str = "rule"
    llm_url: Optional[str] = None
    llm_api_key: Optional[str] = None
    llm_model: str = "deepseek-chat"

    def __post_init__(self) -> None:
        if self.env not in ENVS:
            raise ValueError(f"env must be one of {list(ENVS)}, got {self.env!r}")
        if self.asr_provider not in ASR_PROVIDERS:
            raise ValueError(f"asr_provider must be one of {list(ASR_PROVIDERS)}")
        if self.llm_provider not in LLM_PROVIDERS:
            raise ValueError(f"llm_provider must be one of {list(LLM_PROVIDERS)}")
        if self.token_ttl_seconds <= 0:
            raise ValueError("token_ttl_seconds must be positive")
        if self.env == "production":
            if self.secret == DEFAULT_DEV_SECRET:
                raise ValueError("ANCHOR_SECRET must be changed in production")
            if self.asr_provider == "http" and not self.asr_url:
                raise ValueError("ANCHOR_ASR_URL is required for the http ASR provider")
            if self.llm_provider == "http" and not self.llm_url:
                raise ValueError("ANCHOR_LLM_URL is required for the http LLM provider")

    @property
    def is_dev(self) -> bool:
        return self.env == "dev"

    def with_(self, **changes: Any) -> "Settings":
        return replace(self, **changes)

    @classmethod
    def from_env(cls) -> "Settings":
        return cls(
            env=_env("ANCHOR_ENV", "dev"),
            secret=_env("ANCHOR_SECRET", DEFAULT_DEV_SECRET),
            db_path=_env("ANCHOR_DB_PATH", str(BACKEND_DIR / "data" / "anchor.db")),
            timezone=_env("ANCHOR_TIMEZONE", "Asia/Shanghai"),
            token_ttl_seconds=_env_int("ANCHOR_TOKEN_TTL_SECONDS", 86400),
            worker_interval_seconds=_env_int("ANCHOR_WORKER_INTERVAL_SECONDS", 60),
            job_lease_seconds=_env_int("ANCHOR_JOB_LEASE_SECONDS", 120),
            asr_provider=_env("ANCHOR_ASR_PROVIDER", "fake"),
            asr_url=os.environ.get("ANCHOR_ASR_URL") or None,
            asr_api_key=os.environ.get("ANCHOR_ASR_API_KEY") or None,
            asr_model=_env("ANCHOR_ASR_MODEL", "whisper-1"),
            llm_provider=_env("ANCHOR_LLM_PROVIDER", "rule"),
            llm_url=os.environ.get("ANCHOR_LLM_URL") or None,
            llm_api_key=os.environ.get("ANCHOR_LLM_API_KEY") or None,
            llm_model=_env("ANCHOR_LLM_MODEL", "deepseek-chat"),
        )
