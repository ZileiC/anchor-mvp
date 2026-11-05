"""Provider adapters (ASR, LLM, notifications).

Business code depends on the protocols in ``base.py``; tests inject fakes.
"""

from __future__ import annotations

from typing import Any, Optional

from ..clock import Clock
from ..config import Settings
from ..db import Database
from .asr_fake import FakeASR
from .asr_http import HttpASR
from .base import ASRAdapter, LLMAdapter, NotifierProtocol
from .llm_http import HttpLLM
from .llm_rule import RuleLLM
from .notifier import DatabaseNotifier


def build_providers(settings: Settings, clock: Clock, db: Database) -> dict[str, Any]:
    """Default adapters for this deployment; tests override individual entries."""
    if settings.asr_provider == "http":
        asr: ASRAdapter = HttpASR(
            settings.asr_url or "", api_key=settings.asr_api_key, model=settings.asr_model
        )
    else:
        asr = FakeASR()
    if settings.llm_provider == "http":
        llm: LLMAdapter = HttpLLM(
            settings.llm_url or "", api_key=settings.llm_api_key, model=settings.llm_model
        )
    else:
        llm = RuleLLM()
    notifier: NotifierProtocol = DatabaseNotifier(db, clock)
    return {"asr": asr, "llm": llm, "notifier": notifier}


__all__ = [
    "ASRAdapter",
    "LLMAdapter",
    "NotifierProtocol",
    "FakeASR",
    "HttpASR",
    "HttpLLM",
    "RuleLLM",
    "DatabaseNotifier",
    "build_providers",
]
