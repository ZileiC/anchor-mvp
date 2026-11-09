"""Provider adapters (ASR, LLM, notifications).

Business code depends on the protocols in ``base.py``; tests inject fakes.
Configuration lives in ``config.py`` (stored row -> environment -> offline
default) so the Settings screen can swap adapters without a restart.
"""

from __future__ import annotations

from typing import Any, Optional

from ..clock import Clock
from ..config import Settings
from ..db import Database
from .asr_fake import FakeASR
from .asr_http import HttpASR
from .asr_windows import WindowsSapiASR
from .base import ASRAdapter, LLMAdapter, NotifierProtocol
from .config import (
    DEFAULT_LLM_BASE_URL,
    DEFAULT_LLM_MODEL,
    ProviderConfig,
    build_asr,
    build_llm,
    describe_providers,
    load_provider_settings,
    mask_key,
    resolve_asr,
    resolve_llm,
    update_provider_settings,
)
from .llm_http import HttpLLM
from .llm_rule import RuleLLM
from .notifier import DatabaseNotifier
from .unavailable import UnavailableASR, UnavailableLLM


def build_providers(
    settings: Settings,
    clock: Clock,
    db: Database,
    *,
    transport: Optional[Any] = None,
) -> dict[str, Any]:
    """Default adapters for this deployment; tests override individual entries."""
    stored = load_provider_settings(db)
    notifier: NotifierProtocol = DatabaseNotifier(db, clock)
    return {
        "asr": build_asr(resolve_asr(settings, stored), transport=transport),
        "llm": build_llm(resolve_llm(settings, stored), transport=transport),
        "notifier": notifier,
    }


__all__ = [
    "ASRAdapter",
    "LLMAdapter",
    "NotifierProtocol",
    "FakeASR",
    "HttpASR",
    "HttpLLM",
    "RuleLLM",
    "UnavailableASR",
    "UnavailableLLM",
    "WindowsSapiASR",
    "DatabaseNotifier",
    "ProviderConfig",
    "DEFAULT_LLM_BASE_URL",
    "DEFAULT_LLM_MODEL",
    "build_asr",
    "build_llm",
    "build_providers",
    "describe_providers",
    "load_provider_settings",
    "mask_key",
    "resolve_asr",
    "resolve_llm",
    "update_provider_settings",
]
