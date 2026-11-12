"""The packaged backend's bundled credentials (2026-11-12).

A build that only replies from the offline rule model is not "ready to use": the
person who unpacks the zip has no key of their own. ``entrypoint._apply_bundle_credentials``
fills the model names/endpoints and, when ``config/credentials.env`` exists next to
the exe, the keys — using ``os.environ.setdefault`` so nothing a developer or a
family member has already set is ever overridden.
"""

from __future__ import annotations

import os

import pytest

from app.entrypoint import _apply_bundle_credentials, _read_dotenv


@pytest.fixture(autouse=True)
def _clean(monkeypatch, tmp_path):
    """No ANCHOR_* variable leaks in from the machine running the tests."""
    for name in (
        "ANCHOR_LLM_API_KEY",
        "ANCHOR_LLM_PROVIDER",
        "ANCHOR_LLM_URL",
        "ANCHOR_LLM_BASE_URL",
        "ANCHOR_LLM_MODEL",
        "ANCHOR_ASR_API_KEY",
        "ANCHOR_ASR_PROVIDER",
        "ANCHOR_ASR_URL",
        "ANCHOR_ASR_BASE_URL",
        "ANCHOR_ASR_MODEL",
        "ANCHOR_DEMO_CREDENTIALS",
    ):
        monkeypatch.delenv(name, raising=False)
    # app_base_dir() finds the exe/pyinstaller dir; point it at the tmp tree.
    import app.entrypoint as entrypoint

    monkeypatch.setattr(entrypoint, "app_base_dir", lambda: tmp_path)
    yield


def _write_credentials(tmp_path, text):
    folder = tmp_path / "config"
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "credentials.env").write_text(text, encoding="utf-8")


def test_dotenv_reader_ignores_comments_and_blanks(tmp_path):
    path = tmp_path / "x.env"
    path.write_text(
        "# a comment\n\nANCHOR_LLM_API_KEY='sk-test'\nASR=plain value\nbroken line\n",
        encoding="utf-8",
    )
    values = _read_dotenv(path)
    assert values == {"ANCHOR_LLM_API_KEY": "sk-test", "ASR": "plain value"}
    assert _read_dotenv(tmp_path / "missing.env") == {}


def test_models_are_filled_in_so_a_fresh_install_is_not_offline(tmp_path):
    _apply_bundle_credentials()
    assert os.environ["ANCHOR_LLM_MODEL"] == "deepseek-flash"
    assert os.environ["ANCHOR_LLM_BASE_URL"] == "https://api.deepseek.com"
    assert os.environ["ANCHOR_ASR_BASE_URL"] == "https://api.siliconflow.cn/v1"
    # No key without a credential file, so no provider claim is made.
    assert "ANCHOR_LLM_PROVIDER" not in os.environ
    assert "ANCHOR_ASR_PROVIDER" not in os.environ


def test_the_bundled_key_is_used_when_nothing_was_set(tmp_path):
    _write_credentials(tmp_path, "ANCHOR_LLM_API_KEY=sk-bundled\nANCHOR_ASR_API_KEY=sk-asr\n")
    _apply_bundle_credentials()
    assert os.environ["ANCHOR_LLM_PROVIDER"] == "http"
    assert os.environ["ANCHOR_LLM_URL"] == "https://api.deepseek.com"
    assert os.environ["ANCHOR_ASR_PROVIDER"] == "http"
    assert os.environ["ANCHOR_ASR_URL"] == "https://api.siliconflow.cn/v1"


def test_an_explicit_environment_always_wins(tmp_path, monkeypatch):
    _write_credentials(tmp_path, "ANCHOR_LLM_API_KEY=sk-bundled\nANCHOR_LLM_MODEL=other-model\n")
    monkeypatch.setenv("ANCHOR_LLM_API_KEY", "sk-mine")
    monkeypatch.setenv("ANCHOR_LLM_MODEL", "my-model")
    _apply_bundle_credentials()
    assert os.environ["ANCHOR_LLM_API_KEY"] == "sk-mine"
    assert os.environ["ANCHOR_LLM_MODEL"] == "my-model"


def test_the_credentials_path_can_be_pointed_elsewhere(tmp_path, monkeypatch):
    other = tmp_path / "elsewhere.env"
    other.write_text("ANCHOR_ASR_API_KEY=sk-from-env\n", encoding="utf-8")
    monkeypatch.setenv("ANCHOR_DEMO_CREDENTIALS", str(other))
    _apply_bundle_credentials()
    assert os.environ["ANCHOR_ASR_PROVIDER"] == "http"
