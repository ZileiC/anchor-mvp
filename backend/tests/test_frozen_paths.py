"""Frozen-bundle path resolution (PyInstaller ``sys._MEIPASS``) without PyInstaller.

These tests fake the two attributes PyInstaller sets — ``sys.frozen`` and
``sys._MEIPASS`` — so the resolvers in ``app/paths.py`` can be exercised in a
normal pytest run. ``test_migrate_reads_migrations_from_meipass`` additionally
proves the migration runner really reads the bundle directory, not the checkout.
"""

from __future__ import annotations

import shutil
import sys
from pathlib import Path

import pytest

import app.paths as paths
from app.activities.engine import ActivityEngine
from app.clock import Clock
from app.db import Database

BACKEND_DIR = Path(paths.__file__).resolve().parent.parent
REPO_ROOT = BACKEND_DIR.parent


@pytest.fixture
def fake_meipass(tmp_path, monkeypatch) -> Path:
    """Pretend PyInstaller unpacked the bundle into ``tmp_path``."""
    bundle = tmp_path / "bundle"
    bundle.mkdir()
    monkeypatch.setattr(sys, "_MEIPASS", str(bundle), raising=False)
    return bundle


@pytest.fixture
def fake_executable(tmp_path, monkeypatch) -> Path:
    """Pretend the process is a frozen ``anchor_backend.exe`` in ``tmp_path/exe``."""
    exe_dir = tmp_path / "exe"
    exe_dir.mkdir()
    monkeypatch.setattr(sys, "frozen", True, raising=False)
    monkeypatch.setattr(sys, "executable", str(exe_dir / "anchor_backend.exe"))
    return exe_dir


# -- read-only resources ----------------------------------------------------
def test_migrations_dir_in_checkout_is_unchanged(monkeypatch):
    monkeypatch.delattr(sys, "_MEIPASS", raising=False)
    assert paths.migrations_dir() == BACKEND_DIR / "migrations"
    assert paths.migrations_dir().is_dir()


def test_activities_content_in_checkout_is_unchanged(monkeypatch):
    monkeypatch.delattr(sys, "_MEIPASS", raising=False)
    content = paths.activities_content_path()
    assert content == REPO_ROOT / "content" / "activities.json"
    assert content.is_file()


def test_migrations_dir_uses_meipass_when_frozen(fake_meipass):
    assert paths.migrations_dir() == fake_meipass / "migrations"


def test_activities_content_uses_meipass_when_frozen(fake_meipass):
    assert paths.activities_content_path() == fake_meipass / "content" / "activities.json"


def test_bundle_dir_returns_the_meipass_directory(fake_meipass):
    assert paths.bundle_dir() == fake_meipass


def test_bundle_dir_returns_none_without_meipass(monkeypatch):
    monkeypatch.delattr(sys, "_MEIPASS", raising=False)
    assert paths.bundle_dir() is None


# -- writable data directory ------------------------------------------------
def test_app_base_dir_in_checkout_is_backend(monkeypatch):
    monkeypatch.setattr(sys, "frozen", False, raising=False)
    assert paths.app_base_dir() == BACKEND_DIR


def test_app_base_dir_frozen_is_the_executable_directory(fake_executable):
    assert paths.is_frozen() is True
    assert paths.app_base_dir() == fake_executable


def test_resolve_db_path_honours_anchor_db_path(tmp_path):
    configured = tmp_path / "elsewhere" / "custom.db"
    resolved = paths.resolve_db_path({"ANCHOR_DB_PATH": str(configured)}, base_dir=tmp_path)
    assert resolved == str(configured)


def test_resolve_db_path_keeps_memory_database():
    assert paths.resolve_db_path({"ANCHOR_DB_PATH": ":memory:"}) == ":memory:"


def test_resolve_db_path_defaults_to_data_next_to_the_base(tmp_path):
    resolved = paths.resolve_db_path({}, base_dir=tmp_path)
    assert resolved == str(tmp_path / "data" / "anchor.db")


def test_resolve_db_path_falls_back_to_local_appdata(tmp_path):
    appdata = tmp_path / "appdata" / "Local"
    resolved = paths.resolve_db_path(
        {"LOCALAPPDATA": str(appdata)},
        base_dir=tmp_path / "readonly-exe",
        writable=lambda directory: False,
    )
    assert resolved == str(appdata / "Anchor" / "anchor.db")


def test_resolve_db_path_creates_the_data_directory(tmp_path):
    resolved = paths.resolve_db_path({}, base_dir=tmp_path / "exe")
    assert Path(resolved).parent.is_dir()


# -- integration: the resolvers are actually wired in -----------------------
def test_migrate_reads_migrations_from_meipass(fake_meipass, tmp_path):
    shutil.copytree(BACKEND_DIR / "migrations", fake_meipass / "migrations")
    database = Database(tmp_path / "frozen.db")
    try:
        applied = database.migrate()
    finally:
        database.close()
    assert applied == ["001_init.sql", "002_provider_settings.sql"]


def test_activity_engine_reads_content_from_meipass(fake_meipass):
    source = REPO_ROOT / "content" / "activities.json"
    (fake_meipass / "content").mkdir()
    shutil.copy2(source, fake_meipass / "content" / "activities.json")
    database = Database(":memory:")
    try:
        engine = ActivityEngine(database, Clock())
        assert engine.content()["activities"], "bundled activity pack is empty"
    finally:
        database.close()
