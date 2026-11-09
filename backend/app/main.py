"""FastAPI application factory and ASGI entry point."""
from __future__ import annotations

from typing import Any, Optional

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .clock import Clock
from .config import Settings
from .context import AppContext
from .db import Database
from .errors import install_error_handlers
from .api import (
    activities,
    auth_routes,
    checkins,
    consents,
    contacts,
    data,
    digests,
    health,
    memories,
    notifications,
    preferences,
    providers,
    relationships,
    sessions,
)

VERSION = "0.1.0"

OFFLINE_CAPABILITIES = ["stop", "settings", "cached_activities", "system_calling"]

ROUTERS = (
    health,
    auth_routes,
    providers,
    relationships,
    consents,
    preferences,
    checkins,
    sessions,
    memories,
    activities,
    digests,
    contacts,
    notifications,
    data,
)


def create_app(
    settings: Optional[Settings] = None,
    clock: Optional[Clock] = None,
    providers: Optional[dict[str, Any]] = None,
    provider_transport: Optional[Any] = None,
) -> FastAPI:
    settings = settings or Settings.from_env()

    application = FastAPI(title="Anchor API", version=VERSION)
    database = Database(settings.db_path)
    database.migrate()
    active_clock = clock or Clock()

    application.state.settings = settings
    application.state.db = database
    application.state.clock = active_clock
    application.state.ctx = AppContext(
        settings, database, active_clock, providers, provider_transport
    )
    application.state.providers = application.state.ctx.providers

    install_error_handlers(application)
    application.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_methods=["*"],
        allow_headers=["*"],
    )
    for module in ROUTERS:
        application.include_router(module.router, prefix="/api/v1")

    @application.on_event("shutdown")
    def _close_db() -> None:  # pragma: no cover - lifecycle glue
        database.close()

    return application


app = create_app()
