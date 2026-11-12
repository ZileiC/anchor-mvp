"""PyInstaller entry point for the packaged backend (``anchor_backend.exe``).

The Windows demo ships no Python: this module is the whole server process.

* the database lives next to the executable (``<exe dir>/data/anchor.db``), with
  ``ANCHOR_DB_PATH`` as an explicit override and ``%LOCALAPPDATA%\\Anchor`` as the
  fallback when the exe directory is not writable (``app/paths.py``);
* an empty database is seeded with the demo world on first start, so the demo
  needs no separate ``seed_demo.py`` step;
* the server binds ``127.0.0.1:8077`` (``ANCHOR_PORT`` overrides) and exits with
  code 0 when the port is already in use — that means the desktop app already
  started a backend, and the second copy must disappear quietly;
* under ``--noconsole`` there is no stdout/stderr, so both are redirected to
  ``<data dir>/backend.log`` before anything can print or log.
"""

from __future__ import annotations

import os
import socket
import sys
import traceback
from pathlib import Path
from typing import TextIO

import uvicorn

from app.config import Settings
from app.paths import DATA_DIR_NAME, app_base_dir, is_frozen, resolve_db_path

LOG_FILE_NAME = "backend.log"

# The bundle the family does not have to fill in, 2026-11-12.
#
# Shipping a build that only replies from the offline rule model is not "ready to
# use": the person who unpacks the zip has no DeepSeek key and no speech-recognition
# key, so the senior's first sentence would come back as a template and the
# microphone would answer "not configured".
#
# These are applied with os.environ.setdefault, i.e. ONLY when the environment does
# not already say something, and a key saved in the app's own settings still wins
# (see app/providers/config.py: stored row -> environment -> offline default). So a
# family that enters their own keys is unaffected, and a developer's shell override
# still works.
#
# The key lives per install, in config\credentials.env next to the executable:
#   ANCHOR_DEMO_CREDENTIALS=<path to a .env file with ANCHOR_LLM_API_KEY=...>
# The real keys are NEVER in the repository or in this source file (the file is
# gitignored and lines beginning with # are ignored). Keys are per-install anyway:
# DeepSeek and SiliconFlow keys are not shareable, and the hosted build's keys
# cannot be silently put in a public zip.
BUNDLE_ENV_FILE = "ANCHOR_DEMO_CREDENTIALS"
BUNDLE_DEFAULT_MODELS = (
    ("ANCHOR_LLM_BASE_URL", "https://api.deepseek.com"),
    ("ANCHOR_LLM_MODEL", "deepseek-flash"),
    ("ANCHOR_ASR_BASE_URL", "https://api.siliconflow.cn/v1"),
    ("ANCHOR_ASR_MODEL", "Qwen/Qwen3-ASR-1.7B"),
)


def _read_dotenv(path: Path) -> dict[str, str]:
    """Minimal ``KEY=value`` reader: comments, blanks, optional quotes."""
    values: dict[str, str] = {}
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return values
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and value:
            values[key] = value
    return values


def _apply_bundle_credentials() -> None:
    """Make the frozen build usable out of the box, without overriding anyone."""
    for name, value in BUNDLE_DEFAULT_MODELS:
        os.environ.setdefault(name, value)

    candidates: list[Path] = []
    explicit = os.environ.get(BUNDLE_ENV_FILE)
    if explicit:
        candidates.append(Path(explicit).expanduser())
    candidates.append(app_base_dir() / "config" / "credentials.env")
    # Inside the one-file exe the bundled file is extracted to _MEIPASS/config.
    meipass = getattr(sys, "_MEIPASS", None)
    if meipass:
        candidates.append(Path(meipass) / "config" / "credentials.env")
    for candidate in candidates:
        if not candidate.is_file():
            continue
        for name, value in _read_dotenv(candidate).items():
            os.environ.setdefault(name, value)
        break

    # A key with no explicit provider mode would leave the app on the offline rule
    # model (that is app/providers/config.py's documented default); say "http" only
    # when we actually have a key for it.
    if os.environ.get("ANCHOR_LLM_API_KEY"):
        os.environ.setdefault("ANCHOR_LLM_PROVIDER", "http")
        os.environ.setdefault("ANCHOR_LLM_URL", os.environ["ANCHOR_LLM_BASE_URL"])
    if os.environ.get("ANCHOR_ASR_API_KEY"):
        os.environ.setdefault("ANCHOR_ASR_PROVIDER", "http")
        os.environ.setdefault("ANCHOR_ASR_URL", os.environ["ANCHOR_ASR_BASE_URL"])


# -- process plumbing -----------------------------------------------------
def _log_dir(db_path: str) -> Path:
    if db_path != ":memory:":
        return Path(db_path).expanduser().parent
    return app_base_dir() / DATA_DIR_NAME


def _ensure_streams(db_path: str) -> None:
    """Give a windowed exe writable stdout/stderr (a file, never ``None``)."""
    if sys.stdout is not None and sys.stderr is not None:
        return
    stream: TextIO
    try:
        directory = _log_dir(db_path)
        directory.mkdir(parents=True, exist_ok=True)
        stream = open(directory / LOG_FILE_NAME, "a", encoding="utf-8", buffering=1)
    except OSError:
        stream = open(os.devnull, "a", encoding="utf-8")
    if sys.stdout is None:
        sys.stdout = stream
    if sys.stderr is None:
        sys.stderr = stream


# -- port handling --------------------------------------------------------
def _port_listening(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.settimeout(0.5)
        return probe.connect_ex(("127.0.0.1", port)) == 0


def _port_available(port: int) -> bool:
    if _port_listening(port):
        return False
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.bind(("127.0.0.1", port))
    except OSError:
        return False
    return True


def _is_port_in_use_error(exc: BaseException) -> bool:
    text = f"{exc}".lower()
    return (
        "address already in use" in text
        or "winerror 10048" in text
        or "10048" in text
        or "only one usage" in text
    )


# -- server ---------------------------------------------------------------
def main() -> int:
    db_path = resolve_db_path()
    # Model names/endpoints and (when the bundle ships them) the keys, before any
    # Settings.from_env() reads the environment.
    _apply_bundle_credentials()
    # When no key was bundled, fall back to the real offline Windows SAPI
    # recognizer if this machine has one, and stay honest otherwise.
    os.environ.setdefault("ANCHOR_ASR_PROVIDER", "auto")
    # app/main.py builds a module-level ``app`` when imported (uvicorn app.main:app
    # in development). Point that import at the same file so a frozen run never
    # creates a second database inside the PyInstaller _MEIPASS directory.
    os.environ["ANCHOR_DB_PATH"] = db_path
    _ensure_streams(db_path)

    settings = Settings.from_env().with_(db_path=db_path)
    port = int(os.environ.get("ANCHOR_PORT", "8077"))
    # The packaged desktop build is the demo server for a phone on the same
    # Wi-Fi (the Flutter app is a client; ASR/TTS/LLM/data all live here), so it
    # listens on every interface when frozen. A development `uvicorn app.main:app`
    # keeps 127.0.0.1. Never expose this beyond a trusted LAN: there is no TLS
    # and the demo identity is a dev login.
    default_host = "0.0.0.0" if is_frozen() else "127.0.0.1"
    host = os.environ.get("ANCHOR_HOST", default_host)

    if not _port_available(port):
        # Another backend (started by the desktop app) already owns the port.
        return 0

    from app.main import create_app  # deferred: see the ANCHOR_DB_PATH note above

    application = create_app(settings)
    database = application.state.db
    if int(database.scalar("SELECT COUNT(*) AS n FROM users") or 0) == 0:
        from app.demo_seed import seed_demo

        seed_demo(database, application.state.clock, settings, demo_window=True)

    try:
        uvicorn.run(application, host=host, port=port, log_level="warning")
    except SystemExit as exc:
        code = exc.code if isinstance(exc.code, int) else (0 if exc.code is None else 1)
        if code == 0:
            return 0
        if _port_listening(port):
            return 0
        raise
    except OSError as exc:
        if _is_port_in_use_error(exc) or _port_listening(port):
            return 0
        raise
    return 0


def _run() -> int:
    try:
        return main()
    except BaseException:  # noqa: BLE001 - a windowed crash must still reach backend.log
        if sys.stderr is not None:
            traceback.print_exc()
        return 1


if __name__ == "__main__":
    raise SystemExit(_run())
