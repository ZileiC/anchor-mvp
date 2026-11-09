"""Filesystem layout for the checkout and for the PyInstaller bundle (SPEC §2).

A PyInstaller one-file build unpacks its data files into a temporary directory
(``sys._MEIPASS``) that is *not* the directory holding ``anchor_backend.exe``:
read-only resources therefore live next to ``_MEIPASS`` while the writable demo
data must live next to the executable. ``Path(__file__)`` arithmetic only holds
in the checkout, so every path is resolved here and unit-tested with a fake
``_MEIPASS`` (``tests/test_frozen_paths.py``).

Layouts:

===========  ==========================  =====================================
mode         read-only resources         writable data (DB, log)
===========  ==========================  =====================================
checkout     ``<backend>/migrations``     ``<backend>/data/anchor.db``
             ``<repo>/content``
frozen       ``<_MEIPASS>/migrations``    ``<exe dir>/data/anchor.db``
             ``<_MEIPASS>/content``
===========  ==========================  =====================================

When the executable directory is not writable (Program Files, read-only media)
the database falls back to ``%LOCALAPPDATA%/Anchor/anchor.db``.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path
from typing import Callable, Mapping, Optional

APP_DIR_NAME = "Anchor"
DATA_DIR_NAME = "data"
DB_FILE_NAME = "anchor.db"


def is_frozen() -> bool:
    """True inside a PyInstaller bundle (``--onefile`` or ``--onedir``)."""
    return bool(getattr(sys, "frozen", False))


def bundle_dir() -> Optional[Path]:
    """The PyInstaller extraction directory (``sys._MEIPASS``), else ``None``.

    Read at call time on purpose: tests inject a fake ``_MEIPASS`` after import.
    """
    root = getattr(sys, "_MEIPASS", None)
    return Path(root).resolve() if root else None


def app_base_dir() -> Path:
    """Directory that owns runtime data: the exe dir when frozen, else backend/."""
    if is_frozen():
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent.parent


def package_dir() -> Path:
    """Directory holding bundled read-only resources (``_MEIPASS`` when frozen)."""
    bundled = bundle_dir()
    return bundled if bundled is not None else app_base_dir()


def migrations_dir() -> Path:
    """Directory with the ``NNN_*.sql`` schema migrations."""
    return package_dir() / "migrations"


def activities_content_path() -> Path:
    """The curated activity pack (``content/activities.json``)."""
    bundled = bundle_dir()
    if bundled is not None:
        return bundled / "content" / "activities.json"
    return app_base_dir().parent / "content" / "activities.json"


def _probe_writable(directory: Path) -> bool:
    """Create/remove a probe file: the only reliable writability test on Windows."""
    try:
        directory.mkdir(parents=True, exist_ok=True)
        probe = directory / f".anchor-write-{os.getpid()}.tmp"
        probe.write_text("", encoding="utf-8")
        probe.unlink()
        return True
    except OSError:
        return False


def local_app_data(env: Mapping[str, str]) -> Path:
    """``%LOCALAPPDATA%`` (with a portable fallback when the variable is absent)."""
    raw = env.get("LOCALAPPDATA")
    if raw:
        return Path(raw)
    return Path.home() / "AppData" / "Local"


def resolve_db_path(
    env: Optional[Mapping[str, str]] = None,
    *,
    base_dir: Optional[Path] = None,
    writable: Callable[[Path], bool] = _probe_writable,
) -> str:
    """Choose the SQLite file for this process.

    1. ``ANCHOR_DB_PATH`` when set (``:memory:`` included);
    2. ``<base>/data/anchor.db`` when that directory is writable;
    3. ``%LOCALAPPDATA%/Anchor/anchor.db`` otherwise.
    """
    environ = os.environ if env is None else env
    configured = environ.get("ANCHOR_DB_PATH")
    if configured:
        return configured
    base = Path(base_dir) if base_dir is not None else app_base_dir()
    primary = base / DATA_DIR_NAME / DB_FILE_NAME
    if writable(primary.parent):
        return str(primary)
    return str(local_app_data(environ) / APP_DIR_NAME / DB_FILE_NAME)
