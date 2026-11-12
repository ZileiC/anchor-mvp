"""Offline Windows SAPI speech recognition: adapter behaviour and auto selection.

The subprocess runner is injected, so these tests never launch PowerShell; the
live recognizer is exercised manually (see the task report).
"""

from __future__ import annotations

import subprocess
import types
from pathlib import Path

import pytest

import app.providers.asr_windows as asr_windows
from app.clock import FakeClock
from app.config import Settings
from app.db import Database
from app.errors import AppError
from app.providers import build_providers
from app.providers.asr_windows import WindowsSapiASR
from app.providers.unavailable import UnavailableASR

WAV_BYTES = b"RIFF" + b"\x00" * 4 + b"WAVE" + b"fmt " + b"\x00" * 32 + b"data" + b"\x00" * 8


def _runner_returning(code: int, text: str | None = None):
    def run(audio_path: Path, out_path: Path) -> int:
        assert audio_path.read_bytes() == WAV_BYTES
        if text is not None:
            # System.Speech writes UTF-8 with a BOM (Encoding.UTF8 in .NET FX).
            out_path.write_bytes(b"\xef\xbb\xbf" + text.encode("utf-8"))
        return code

    return run


def test_sapi_transcribes_a_wav_with_an_injected_runner(tmp_path):
    asr = WindowsSapiASR(runner=_runner_returning(0, "今天天气不错"), workdir=tmp_path)
    assert asr.transcribe(WAV_BYTES, "audio/wav") == "今天天气不错"
    assert list(tmp_path.iterdir()) == []  # every temp file was removed


def test_sapi_strips_whitespace_from_the_recognized_text(tmp_path):
    asr = WindowsSapiASR(runner=_runner_returning(0, "  我想喝水 \r\n"), workdir=tmp_path)
    assert asr.transcribe(WAV_BYTES) == "我想喝水"


def test_sapi_no_result_is_provider_unavailable(tmp_path):
    asr = WindowsSapiASR(runner=_runner_returning(2), workdir=tmp_path)
    with pytest.raises(AppError) as excinfo:
        asr.transcribe(WAV_BYTES)
    error = excinfo.value
    assert error.code == "provider_unavailable"
    assert error.status == 503
    assert "没有听清" in error.message
    assert error.extra["recovery"] == ["retry", "type_instead"]
    assert error.extra["provider"] == "asr"
    assert list(tmp_path.iterdir()) == []


def test_sapi_empty_transcript_is_provider_unavailable(tmp_path):
    asr = WindowsSapiASR(runner=_runner_returning(0, "   "), workdir=tmp_path)
    with pytest.raises(AppError) as excinfo:
        asr.transcribe(WAV_BYTES)
    assert excinfo.value.code == "provider_unavailable"
    assert "没有听清" in excinfo.value.message


def test_sapi_missing_recognizer_exit_code_is_provider_unavailable(tmp_path):
    asr = WindowsSapiASR(runner=_runner_returning(3), workdir=tmp_path)
    with pytest.raises(AppError):
        asr.transcribe(WAV_BYTES)


def test_sapi_process_failure_is_provider_unavailable(tmp_path):
    asr = WindowsSapiASR(runner=_runner_returning(1), workdir=tmp_path)
    with pytest.raises(AppError) as excinfo:
        asr.transcribe(WAV_BYTES)
    assert excinfo.value.code == "provider_unavailable"
    assert list(tmp_path.iterdir()) == []


def test_sapi_timeout_is_provider_unavailable_and_cleans_up(tmp_path):
    def run(audio_path: Path, out_path: Path) -> int:
        raise subprocess.TimeoutExpired(cmd="powershell", timeout=25)

    asr = WindowsSapiASR(runner=run, workdir=tmp_path)
    with pytest.raises(AppError) as excinfo:
        asr.transcribe(WAV_BYTES)
    assert excinfo.value.code == "provider_unavailable"
    assert list(tmp_path.iterdir()) == []


def test_sapi_rejects_non_wav_audio_without_running_anything(tmp_path):
    called: list[tuple[Path, Path]] = []

    def run(audio_path: Path, out_path: Path) -> int:
        called.append((audio_path, out_path))
        return 0

    asr = WindowsSapiASR(runner=run, workdir=tmp_path)
    with pytest.raises(AppError) as excinfo:
        asr.transcribe(b"not a wav file", "audio/webm")
    assert excinfo.value.code == "provider_unavailable"
    assert "WAV" in excinfo.value.message
    assert called == []


# -- auto-mode selection ---------------------------------------------------
def _settings(tmp_path, **changes) -> Settings:
    base = dict(env="test", db_path=str(tmp_path / "a.db"), asr_provider="auto")
    base.update(changes)
    return Settings(**base)


def test_auto_mode_uses_windows_sapi_when_a_recognizer_exists(monkeypatch, tmp_path):
    monkeypatch.setattr(asr_windows, "windows_sapi_available", lambda: True)
    db = Database(tmp_path / "a.db")
    db.migrate()
    try:
        providers = build_providers(_settings(tmp_path), FakeClock(), db)
        assert isinstance(providers["asr"], WindowsSapiASR)
    finally:
        db.close()


def test_auto_mode_is_honest_without_a_recognizer(monkeypatch, tmp_path):
    monkeypatch.setattr(asr_windows, "windows_sapi_available", lambda: False)
    db = Database(tmp_path / "a.db")
    db.migrate()
    try:
        providers = build_providers(_settings(tmp_path), FakeClock(), db)
        assert isinstance(providers["asr"], UnavailableASR)
    finally:
        db.close()


def test_windows_sapi_probe_is_cached(monkeypatch):
    calls: list[int] = []

    def probe(timeout: float = 10.0) -> bool:
        calls.append(1)
        return True

    monkeypatch.setattr(asr_windows, "sys", types.SimpleNamespace(platform="win32"))
    monkeypatch.setattr(asr_windows, "_probe_recognizers", probe)
    asr_windows.reset_sapi_probe_cache()
    try:
        assert asr_windows.windows_sapi_available() is True
        assert asr_windows.windows_sapi_available() is True
        assert len(calls) == 1
        assert asr_windows.windows_sapi_available(force=True) is True
        assert len(calls) == 2
    finally:
        asr_windows.reset_sapi_probe_cache()


def test_windows_sapi_is_unavailable_off_windows(monkeypatch):
    monkeypatch.setattr(asr_windows, "sys", types.SimpleNamespace(platform="linux"))
    asr_windows.reset_sapi_probe_cache()
    try:
        assert asr_windows.windows_sapi_available() is False
    finally:
        asr_windows.reset_sapi_probe_cache()
