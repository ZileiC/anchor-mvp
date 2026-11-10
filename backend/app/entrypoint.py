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
    # The packaged demo has no ASR key; use the real offline Windows SAPI
    # recognizer when this machine has one, and be honest otherwise.
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
