from __future__ import annotations

import sys
from datetime import datetime, timezone
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent.parent
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

import pytest
from fastapi.testclient import TestClient

from app.clock import FakeClock
from app.config import Settings
from app.main import create_app
from tests import helpers

# 2026-01-05T01:00Z == 09:00 in Asia/Shanghai, inside the default greeting window.
DEFAULT_NOW = datetime(2026, 1, 5, 1, 0, tzinfo=timezone.utc)


@pytest.fixture
def settings(tmp_path: Path) -> Settings:
    return Settings(
        env="test",
        secret="test-secret",
        db_path=str(tmp_path / "anchor-test.db"),
        timezone="Asia/Shanghai",
    )


@pytest.fixture
def fake_clock() -> FakeClock:
    return FakeClock(DEFAULT_NOW)


@pytest.fixture
def app(settings: Settings, fake_clock: FakeClock):
    application = create_app(settings, clock=fake_clock)
    yield application
    application.state.db.close()


@pytest.fixture
def client(app) -> TestClient:
    return TestClient(app, raise_server_exceptions=False)


@pytest.fixture
def clock(app) -> FakeClock:
    return app.state.clock


@pytest.fixture
def make_user(app):
    def factory(role: str, display_name: str = "用户"):
        return helpers.make_user(app, role, display_name)

    return factory


@pytest.fixture
def senior(make_user):
    return make_user("senior", "王阿姨")


@pytest.fixture
def caregiver(make_user):
    return make_user("caregiver", "小梅")


@pytest.fixture
def senior_token(app, senior) -> str:
    return helpers.token_for(app, senior)


@pytest.fixture
def caregiver_token(app, caregiver) -> str:
    return helpers.token_for(app, caregiver)


@pytest.fixture
def linked(app, senior, caregiver):
    return helpers.link_relationship(app, senior, caregiver, status="accepted")


@pytest.fixture
def use_providers(app):
    def apply(**kwargs):
        app.state.ctx.providers.update(kwargs)
        return app.state.ctx.providers

    return apply


@pytest.fixture
def client_production(tmp_path: Path):
    production = Settings(
        env="production",
        secret="production-secret-value",
        db_path=str(tmp_path / "prod.db"),
        timezone="Asia/Shanghai",
    )
    application = create_app(production)
    yield TestClient(application, raise_server_exceptions=False)
    application.state.db.close()
