"""Service container built once per application (see ``create_app``)."""
from __future__ import annotations

from typing import Any, Optional

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
from .providers.config import build_asr, build_llm, load_provider_settings, resolve_asr, resolve_llm
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
        provider_transport: Optional[Any] = None,
    ) -> None:
        self.settings = settings
        self.db = db
        self.clock = clock
        # Test/injection seam: adapters use this httpx transport when set.
        self.provider_transport = provider_transport
        self.providers: dict[str, Any] = providers if providers is not None else {}
        if providers is None:
            # Startup: honour the persisted Settings row, not just the environment.
            self.rebuild_providers()
        else:
            self.providers.setdefault("notifier", DatabaseNotifier(db, clock))

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

    def rebuild_providers(self) -> dict[str, Any]:
        """Rebuild ASR/LLM from the stored settings row, mutating in place.

        The orchestrator (and ``app.state.providers``) hold a reference to this
        very dict, so a PUT to the Settings screen takes effect immediately and
        without a restart.
        """
        stored = load_provider_settings(self.db)
        self.providers["asr"] = build_asr(
            resolve_asr(self.settings, stored), transport=self.provider_transport
        )
        self.providers["llm"] = build_llm(
            resolve_llm(self.settings, stored), transport=self.provider_transport
        )
        self.providers.setdefault("notifier", DatabaseNotifier(self.db, self.clock))
        return self.providers

    def close(self) -> None:
        self.db.close()
