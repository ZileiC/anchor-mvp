"""Service container built once per application (see ``create_app``)."""
from __future__ import annotations

from typing import Any

from .activities.engine import ActivityEngine
from .checkins import CheckinService
from .clock import Clock
from .config import Settings
from .consent import ConsentService
from .conversation.orchestrator import ConversationOrchestrator
from .db import Database
from .memory import MemoryService
from .preferences import PreferencesService
from .providers import build_providers
from .relationships import RelationshipService, ScheduleProposalService


class AppContext:
    def __init__(
        self,
        settings: Settings,
        db: Database,
        clock: Clock,
        providers: dict[str, Any] | None = None,
    ) -> None:
        self.settings = settings
        self.db = db
        self.clock = clock
        self.providers = providers if providers is not None else build_providers(settings, clock, db)

        self.consent = ConsentService(db, clock)
        self.preferences = PreferencesService(db, clock)
        self.relationships = RelationshipService(db, clock)
        self.schedule_proposals = ScheduleProposalService(db, clock, self.preferences)
        self.checkins = CheckinService(db, clock, self.preferences, self.consent)
        self.memory = MemoryService(db, clock, self.consent)
        self.activities = ActivityEngine(db, clock, self.consent, self.preferences)
        self.conversation = ConversationOrchestrator(
            db,
            clock,
            self.providers,
            consent=self.consent,
            preferences=self.preferences,
            memories=self.memory,
            activities=self.activities,
        )

    def close(self) -> None:
        self.db.close()
