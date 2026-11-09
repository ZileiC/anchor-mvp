"""Real, offline speech recognition on Windows via System.Speech (SAPI 5.1).

The packaged Windows demo has no ASR API key, but the machine ships a Chinese
SAPI recognizer (``MS-2052-80-DESK`` on this box). ``SpeechRecognitionEngine``
accepts the 16 kHz mono PCM WAV that the Flutter ``record`` plugin produces, so
voice input is real without any network call:

* the audio is written to a throw-away temp file (never persisted, never logged),
* ``powershell.exe -File asr_sapi.ps1 <wav> <out.txt>`` runs the recognizer,
* the transcript is read back as UTF-8 and the temp directory is removed.

Nothing is ever fabricated: no recognizer, silence, a non-WAV payload or a failed
process all raise ``provider_unavailable`` with ``recovery=["type_instead"]``.

The subprocess runner is injectable (``runner=``) so unit tests never launch
PowerShell, and ``windows_sapi_available()`` probes the recognizers once and
caches the answer.
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Callable, Optional

from ..errors import provider_unavailable
from .unavailable import ASR_BAD_AUDIO

RECOVERY = ["retry", "type_instead"]
NOT_HEARD = "没有听清，请再说一遍，或者打字输入。"

# ASCII only on purpose: Windows PowerShell 5.1 decodes a BOM-less .ps1 as ANSI,
# so Chinese here would be mojibake. The transcript never travels through
# stdout; it is written to out.txt as UTF-8.
_RECOGNIZE_SCRIPT = r"""
param(
    [Parameter(Mandatory = $true)][string]$AudioPath,
    [Parameter(Mandatory = $true)][string]$OutPath
)
$ErrorActionPreference = 'Stop'
try { Add-Type -AssemblyName System.Speech } catch { exit 1 }
try {
    $infos = [System.Speech.Recognition.SpeechRecognitionEngine]::InstalledRecognizers()
} catch { exit 1 }
if ($null -eq $infos -or $infos.Count -eq 0) { exit 3 }
$chosen = $infos | Where-Object { $_.Culture.Name -eq 'zh-CN' } | Select-Object -First 1
if ($null -eq $chosen) { $chosen = $infos | Select-Object -First 1 }
try {
    $engine = New-Object System.Speech.Recognition.SpeechRecognitionEngine($chosen)
    $grammar = New-Object System.Speech.Recognition.DictationGrammar
    $engine.LoadGrammar($grammar)
    $engine.SetInputToWaveFile($AudioPath)
    $result = $engine.Recognize()
    $engine.Dispose()
} catch { exit 1 }
if ($null -eq $result -or [string]::IsNullOrWhiteSpace($result.Text)) { exit 2 }
[System.IO.File]::WriteAllText($OutPath, $result.Text, [System.Text.Encoding]::UTF8)
exit 0
"""

_PROBE_COMMAND = (
    "try { Add-Type -AssemblyName System.Speech } catch { exit 1 }; "
    "try { $r = [System.Speech.Recognition.SpeechRecognitionEngine]::InstalledRecognizers(); "
    "if ($r.Count -gt 0) { exit 0 } } catch { exit 1 }; exit 1"
)

_CREATE_NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)

Runner = Callable[[Path, Path], int]

_AVAILABLE: Optional[bool] = None


def _powershell_executable() -> str:
    return "powershell.exe" if sys.platform == "win32" else "powershell"


def _run_powershell(audio_path: Path, out_path: Path, timeout: float = 25.0) -> int:
    """Run the recognizer script; returns its exit code (raises on timeout)."""
    script_path = audio_path.with_name("asr_sapi.ps1")
    script_path.write_text(_RECOGNIZE_SCRIPT, encoding="utf-8")
    completed = subprocess.run(
        [
            _powershell_executable(),
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(script_path),
            str(audio_path),
            str(out_path),
        ],
        timeout=timeout,
        capture_output=True,
        creationflags=_CREATE_NO_WINDOW,
    )
    return int(completed.returncode)


def _probe_recognizers(timeout: float = 10.0) -> bool:
    """True when this Windows box has at least one SAPI recognizer installed."""
    if sys.platform != "win32":
        return False
    try:
        completed = subprocess.run(
            [
                _powershell_executable(),
                "-NoProfile",
                "-NonInteractive",
                "-Command",
                _PROBE_COMMAND,
            ],
            timeout=timeout,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            creationflags=_CREATE_NO_WINDOW,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return completed.returncode == 0


def windows_sapi_available(*, force: bool = False) -> bool:
    """Probe the SAPI recognizers once per process (cached)."""
    global _AVAILABLE
    if sys.platform != "win32":
        return False
    if force or _AVAILABLE is None:
        _AVAILABLE = _probe_recognizers()
    return bool(_AVAILABLE)


def reset_sapi_probe_cache() -> None:
    """Forget the cached probe result (tests and operator troubleshooting)."""
    global _AVAILABLE
    _AVAILABLE = None


def _looks_like_wav(audio: bytes) -> bool:
    return len(audio) >= 12 and audio[:4] == b"RIFF" and audio[8:12] == b"WAVE"


class WindowsSapiASR:
    """Offline Windows speech-to-text; no API key, no network, no fabrication."""

    def __init__(
        self,
        *,
        runner: Optional[Runner] = None,
        timeout: float = 25.0,
        workdir: Optional[Path] = None,
    ) -> None:
        self._runner: Runner = runner or (
            lambda wav, out: _run_powershell(wav, out, timeout=timeout)
        )
        self.timeout = timeout
        self.workdir = workdir

    def transcribe(self, audio: bytes, mime: str = "audio/wav") -> str:
        if not _looks_like_wav(audio):
            raise provider_unavailable(
                ASR_BAD_AUDIO, recovery=["type_instead"], provider="asr"
            )
        with tempfile.TemporaryDirectory(
            prefix="anchor-asr-", dir=str(self.workdir) if self.workdir else None
        ) as tmp:
            directory = Path(tmp)
            audio_path = directory / "audio.wav"
            out_path = directory / "transcript.txt"
            audio_path.write_bytes(audio)
            try:
                returncode = self._runner(audio_path, out_path)
            except subprocess.TimeoutExpired as exc:
                raise provider_unavailable(
                    NOT_HEARD, recovery=list(RECOVERY), provider="asr"
                ) from exc
            except OSError as exc:
                raise provider_unavailable(
                    NOT_HEARD, recovery=list(RECOVERY), provider="asr"
                ) from exc
            if returncode != 0 or not out_path.exists():
                raise provider_unavailable(
                    NOT_HEARD, recovery=list(RECOVERY), provider="asr"
                )
            text = out_path.read_text(encoding="utf-8-sig").strip()
        if not text:
            raise provider_unavailable(
                NOT_HEARD, recovery=list(RECOVERY), provider="asr"
            )
        return text
