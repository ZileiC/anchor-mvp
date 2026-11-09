"""Effective provider resolution: stored settings -> environment -> offline default.

Resolution order (per section, independently):

1. a stored ``provider_settings`` row whose base URL *and* API key are present
   (this is what the Settings screen writes, so a PUT takes effect live);
2. the ``ANCHOR_*`` environment from :class:`app.config.Settings`;
3. an offline default: the deterministic rule model for the LLM and an honest
   ``UnavailableASR`` for speech (never ``FakeASR``).

Explicit environment modes are honoured when no stored row overrides them:
``ANCHOR_LLM_PROVIDER=none`` / ``ANCHOR_ASR_PROVIDER=none`` produce adapters that
raise ``provider_unavailable``; ``ANCHOR_ASR_PROVIDER=auto`` picks the real
offline Windows SAPI recognizer when one is installed, else ``none``.

Security: the API key is only ever handed to the adapter. ``describe_*`` returns
a masked ``key_hint``; storing is plaintext in the local SQLite file (documented
in ``migrations/002_provider_settings.sql``).
"""

from __future__ import annotations

import sqlite3
from dataclasses import dataclass
from typing import Any, Mapping, Optional

from ..config import Settings
from ..db import Database
from . import asr_windows
from .asr_fake import FakeASR
from .asr_http import HttpASR
from .llm_http import HttpLLM
from .llm_rule import RuleLLM
from .unavailable import (
    ASR_INCOMPLETE,
    ASR_NOT_CONFIGURED,
    LLM_INCOMPLETE,
    LLM_NOT_CONFIGURED,
    UnavailableASR,
    UnavailableLLM,
)

DEFAULT_LLM_BASE_URL = "https://api.deepseek.com"
DEFAULT_LLM_MODEL = "deepseek-chat"
DEFAULT_ASR_MODEL = "whisper-1"

SETTINGS_TABLE = "provider_settings"
ALL_COLUMNS = ("llm_base_url", "llm_api_key", "llm_model", "asr_base_url", "asr_api_key", "asr_model")
SECTION_COLUMNS = {
    "llm": ("llm_base_url", "llm_api_key", "llm_model"),
    "asr": ("asr_base_url", "asr_api_key", "asr_model"),
}


@dataclass(frozen=True)
class ProviderConfig:
    """One resolved provider section (internal; descriptions are built separately)."""

    mode: str  # "http" | "sapi" | "rule" | "fake" | "none"
    base_url: Optional[str] = None
    api_key: Optional[str] = None
    model: str = ""
    source: str = "default"  # "stored" | "env" | "default"

    @property
    def uses_network(self) -> bool:
        return self.mode == "http"

    @property
    def available(self) -> bool:
        """True only for a *real* provider: an HTTP endpoint or a local recognizer.

        The offline rule model and the test fake are usable adapters but they are
        not "configured" providers, and the API is honest about that.
        """
        if self.mode == "http":
            # A stored section is only selected when URL+key are present; an
            # explicit env URL may legitimately point at a keyless local server.
            return bool(self.base_url)
        return self.mode == "sapi"


def _text(value: Any) -> Optional[str]:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def mask_key(key: Optional[str]) -> Optional[str]:
    """A hint that is useful in the UI and useless as a credential."""
    if not key:
        return None
    if len(key) <= 8:
        return "…"
    return f"{key[:3]}…{key[-4:]}"


# -- storage ---------------------------------------------------------------
def load_provider_settings(db: Database) -> Optional[dict[str, Any]]:
    """The singleton settings row, or ``None`` when nothing was saved yet."""
    try:
        return db.query_one(f"SELECT * FROM {SETTINGS_TABLE} WHERE id = 1")
    except sqlite3.OperationalError:
        # A database created before migration 002: behave as "not configured".
        return None


def update_provider_settings(
    db: Database,
    *,
    llm: Optional[Mapping[str, Any]] = None,
    asr: Optional[Mapping[str, Any]] = None,
    updated_at: str,
) -> dict[str, Any]:
    """Merge a partial Settings edit into the singleton row and persist it."""
    current = load_provider_settings(db) or {}
    merged: dict[str, Any] = {column: current.get(column) for column in ALL_COLUMNS}
    for section, changes in (("llm", llm), ("asr", asr)):
        if changes is None:
            continue
        columns = SECTION_COLUMNS[section]
        if changes.get("clear"):
            for column in columns:
                merged[column] = None
            continue
        for column, field in zip(columns, ("base_url", "api_key", "model")):
            value = changes.get(field)
            if value is None:
                continue
            candidate = _text(value)
            if field == "api_key" and not candidate:
                continue  # an empty key keeps the stored key
            merged[column] = candidate
    merged["updated_at"] = updated_at
    db.execute(
        f"INSERT INTO {SETTINGS_TABLE}(id, {', '.join(ALL_COLUMNS)}, updated_at) "
        f"VALUES (1, {', '.join('?' for _ in ALL_COLUMNS)}, ?) "
        f"ON CONFLICT(id) DO UPDATE SET "
        + ", ".join(f"{column} = excluded.{column}" for column in ALL_COLUMNS)
        + ", updated_at = excluded.updated_at",
        tuple(merged[column] for column in ALL_COLUMNS) + (updated_at,),
    )
    return load_provider_settings(db) or {}


# -- resolution ------------------------------------------------------------
def resolve_llm(settings: Settings, stored: Optional[Mapping[str, Any]]) -> ProviderConfig:
    row = stored or {}
    base = _text(row.get("llm_base_url"))
    key = _text(row.get("llm_api_key"))
    model = _text(row.get("llm_model")) or _text(settings.llm_model) or DEFAULT_LLM_MODEL
    if base and key:
        return ProviderConfig("http", base, key, model, "stored")
    mode = settings.llm_provider
    if mode == "http":
        return ProviderConfig(
            "http", _text(settings.llm_url) or DEFAULT_LLM_BASE_URL, _text(settings.llm_api_key), model, "env"
        )
    if mode == "none":
        return ProviderConfig("none", base, key, model, "env")
    return ProviderConfig("rule", None, None, model, "default")


def resolve_asr(settings: Settings, stored: Optional[Mapping[str, Any]]) -> ProviderConfig:
    row = stored or {}
    base = _text(row.get("asr_base_url"))
    key = _text(row.get("asr_api_key"))
    model = _text(row.get("asr_model")) or _text(settings.asr_model) or DEFAULT_ASR_MODEL
    if base and key:
        return ProviderConfig("http", base, key, model, "stored")
    mode = settings.asr_provider
    if mode == "http":
        env_base = _text(settings.asr_url)
        if env_base:
            return ProviderConfig("http", env_base, _text(settings.asr_api_key), model, "env")
        return ProviderConfig("none", None, None, model, "env")
    if mode == "fake":
        return ProviderConfig("fake", None, None, model, "env")
    if mode == "auto":
        if asr_windows.windows_sapi_available():
            return ProviderConfig("sapi", None, None, model, "env")
        return ProviderConfig("none", base, key, model, "env")
    return ProviderConfig("none", base, key, model, "default")


# -- adapter construction --------------------------------------------------
def build_llm(
    config: ProviderConfig,
    *,
    transport: Any = None,
    timeout: Optional[float] = None,
    max_tokens: Optional[int] = None,
):
    if config.mode == "http":
        if not config.available:
            return UnavailableLLM(LLM_INCOMPLETE)
        return HttpLLM(
            config.base_url or "",
            api_key=config.api_key,
            model=config.model,
            timeout=timeout if timeout is not None else 20.0,
            max_tokens=max_tokens if max_tokens is not None else 220,
            transport=transport,
        )
    if config.mode == "none":
        return UnavailableLLM(LLM_NOT_CONFIGURED)
    return RuleLLM()


def build_asr(
    config: ProviderConfig,
    *,
    transport: Any = None,
    timeout: Optional[float] = None,
):
    if config.mode == "http":
        if not config.available:
            return UnavailableASR(ASR_INCOMPLETE)
        return HttpASR(
            config.base_url or "",
            api_key=config.api_key,
            model=config.model,
            timeout=timeout if timeout is not None else 20.0,
            transport=transport,
        )
    if config.mode == "sapi":
        return asr_windows.WindowsSapiASR()
    if config.mode == "fake":
        return FakeASR()
    return UnavailableASR(ASR_NOT_CONFIGURED)


# -- descriptions (never include the key) ----------------------------------
_ENGINE_NAMED = {
    "http": "http",
    "sapi": "windows-sapi",
    "rule": "offline-rule",
    "fake": "fake",
    "none": "none",
}


def _describe(config: ProviderConfig) -> dict[str, Any]:
    return {
        "configured": config.available,
        "base_url": config.base_url,
        "model": config.model,
        "key_hint": mask_key(config.api_key),
        "mode": "http" if config.mode == "http" else "offline",
        "engine": _ENGINE_NAMED.get(config.mode, config.mode),
    }


def describe_providers(settings: Settings, stored: Optional[Mapping[str, Any]]) -> dict[str, Any]:
    return {
        "llm": _describe(resolve_llm(settings, stored)),
        "asr": _describe(resolve_asr(settings, stored)),
        "updated_at": (stored or {}).get("updated_at"),
    }
