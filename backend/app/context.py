"""Service container built once per application (see ``create_app``)."""
from __future__ import annotations

from typing import Any

from .activities.engine import ActivityEngine
from .checkins import CheckinService
from .clock import Clock
from .config import Settings
from .consent import ConsentService
from .contacts import ContactService
from .conversation.orchestrator import ConversationOrchestrator
from .db import Database
from .digests.service import DigestService
from .memory import MemoryService
from .notifications import NotificationService
from .preferences import PreferencesService
from .providers import build_providers
from .providers.notifier import DatabaseNotifier
from .relationships import RelationshipService, ScheduleProposalService
from .storage.retention import DataRightsService, RetentionService


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
        self.notifier = DatabaseNotifier(db, clock)
        self.relationships = RelationshipService(db, clock, self.notifier)
        self.schedule_proposals = ScheduleProposalService(db, clock, self.preferences)
        self.checkins = CheckinService(db, clock, self.preferences, self.consent)
        self.memory = MemoryService(db, clock, self.consent)
        self.activities = ActivityEngine(db, clock, self.consent, self.preferences)
        self.digests = DigestService(
            db, clock, self.consent, self.relationships, self.notifier
        )
        self.contacts = ContactService(db, clock, self.relationships)
        self.notifications = NotificationService(db, clock)
        self.retention = RetentionService(db, clock)
        self.data_rights = DataRightsService(db, clock)
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
