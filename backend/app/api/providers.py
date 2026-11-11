"""Provider settings endpoints: read, configure, and really test the providers.

``GET`` / ``PUT`` expose what the Settings screen needs and never the API key
(only a ``key_hint``). ``PUT`` persists the singleton row and rebuilds the live
adapters in place, so no restart is needed. ``POST`` performs a real one-shot
call against the *current effective* configuration: a short chat completion for
the LLM and a real transcription for the ASR when an audio sample is supplied.
"""

from __future__ import annotations

import base64
import binascii
import time
from typing import Any, Optional
from urllib.parse import urlsplit

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from ..clock import iso_utc
from ..errors import AppError, validation_error
from ..providers.config import (
    build_llm,
    describe_providers,
    load_provider_settings,
    resolve_llm,
    update_provider_settings,
)
from .deps import get_context, require_setup_access

router = APIRouter(tags=["providers"])

PROBE_TIMEOUT_SECONDS = 10.0
PROBE_SYSTEM = "Reply with one short sentence."
PROBE_USER = "你好"
SAMPLE_LIMIT = 200


class ProviderSectionIn(BaseModel):
    base_url: Optional[str] = None
    api_key: Optional[str] = None
    model: Optional[str] = None
    clear: bool = False


class ProvidersIn(BaseModel):
    llm: Optional[ProviderSectionIn] = None
    asr: Optional[ProviderSectionIn] = None


class ProviderTestIn(BaseModel):
    audio_b64: Optional[str] = None
    audio_mime: Optional[str] = None


def _validate_section(name: str, section: ProviderSectionIn) -> None:
    if section.clear:
        return
    if section.base_url is not None and section.base_url.strip():
        parsed = urlsplit(section.base_url.strip())
        if parsed.scheme not in ("http", "https") or not parsed.netloc:
            raise validation_error(f"{name}.base_url must be an http(s) URL")
    if section.model is not None and not section.model.strip():
        raise validation_error(f"{name}.model must not be empty")


def _scrub(text: str, api_key: Optional[str]) -> str:
    """Never echo a credential, even inside a provider error message."""
    cleaned = text.strip() or "provider error"
    if api_key:
        cleaned = cleaned.replace(api_key, "[redacted]")
    return cleaned[:400]


def _error_text(exc: AppError) -> str:
    return f"{exc.code}: {exc.message}"


@router.get("/providers")
def get_providers(
    user: dict[str, Any] = Depends(require_setup_access),
    ctx=Depends(get_context),
) -> dict[str, Any]:
    return describe_providers(ctx.settings, load_provider_settings(ctx.db))


@router.put("/providers")
def put_providers(
    body: ProvidersIn,
    user: dict[str, Any] = Depends(require_setup_access),
    ctx=Depends(get_context),
) -> dict[str, Any]:
    changes: dict[str, Any] = {}
    if body.llm is not None:
        _validate_section("llm", body.llm)
        changes["llm"] = body.llm.model_dump()
    if body.asr is not None:
        _validate_section("asr", body.asr)
        changes["asr"] = body.asr.model_dump()
    stored = update_provider_settings(
        ctx.db, updated_at=iso_utc(ctx.clock.now()), **changes
    )
    ctx.rebuild_providers()
    return describe_providers(ctx.settings, stored)


def _probe_llm(ctx) -> dict[str, Any]:
    stored = load_provider_settings(ctx.db)
    config = resolve_llm(ctx.settings, stored)
    if config.mode != "http" or not config.available:
        return {
            "ok": False,
            "latency_ms": None,
            "reply_sample": None,
            "error": "not_configured: 当前没有配置 HTTP 对话接口（离线模式）",
        }
    adapter = build_llm(
        config,
        transport=ctx.provider_transport,
        timeout=PROBE_TIMEOUT_SECONDS,
        max_tokens=64,
    )
    started = time.perf_counter()
    try:
        reply = adapter.reply(
            PROBE_SYSTEM, [{"role": "user", "content": PROBE_USER}], max_words=20
        )
    except AppError as exc:
        return {
            "ok": False,
            "latency_ms": int((time.perf_counter() - started) * 1000),
            "reply_sample": None,
            "error": _scrub(_error_text(exc), config.api_key),
        }
    except Exception as exc:  # noqa: BLE001 - a diagnostic endpoint reports, never crashes
        return {
            "ok": False,
            "latency_ms": int((time.perf_counter() - started) * 1000),
            "reply_sample": None,
            "error": _scrub(f"{type(exc).__name__}: {exc}", config.api_key),
        }
    return {
        "ok": True,
        "latency_ms": int((time.perf_counter() - started) * 1000),
        "reply_sample": reply[:SAMPLE_LIMIT],
        "error": None,
    }


def _probe_asr(ctx, body: ProviderTestIn) -> dict[str, Any]:
    if not body.audio_b64:
        # No sample was supplied: say so instead of pretending the provider works.
        return {"ok": False, "reason": "no_sample"}
    try:
        audio = base64.b64decode(body.audio_b64, validate=True)
    except (binascii.Error, ValueError):
        return {
            "ok": False,
            "reason": "invalid_sample",
            "error": "audio_b64 is not valid base64",
        }
    if not audio:
        return {"ok": False, "reason": "empty_sample", "error": "audio_b64 is empty"}
    adapter = ctx.providers.get("asr")
    if adapter is None:
        return {"ok": False, "reason": "not_configured", "error": "ASR 还没有配置"}
    started = time.perf_counter()
    try:
        text = adapter.transcribe(audio, body.audio_mime or "audio/wav")
    except AppError as exc:
        return {
            "ok": False,
            "latency_ms": int((time.perf_counter() - started) * 1000),
            "error": _scrub(_error_text(exc), None),
        }
    except Exception as exc:  # noqa: BLE001
        return {
            "ok": False,
            "latency_ms": int((time.perf_counter() - started) * 1000),
            "error": _scrub(f"{type(exc).__name__}: {exc}", None),
        }
    return {
        "ok": True,
        "latency_ms": int((time.perf_counter() - started) * 1000),
        "text_sample": text[:SAMPLE_LIMIT],
        "error": None,
    }


@router.post("/providers/test")
def test_providers(
    body: ProviderTestIn = ProviderTestIn(),
    user: dict[str, Any] = Depends(require_setup_access),
    ctx=Depends(get_context),
) -> dict[str, Any]:
    return {"llm": _probe_llm(ctx), "asr": _probe_asr(ctx, body)}
