"""Consent engine: capabilities, versions, shared enforcement (SPEC §5).

Rules implemented here:
* a missing row means **not allowed** (private by default);
* ``consent_state.version`` increments on every effective change;
* ``PUT /consents`` is version-checked and answers 409 on stale ``base_version``;
* every effective change writes an audit row.
"""

from __future__ import annotations

from typing import Any, Iterable, Optional

from . import audit
from .clock import Clock, iso_utc
from .db import Database
from .errors import AppError, validation_error

CAPABILITIES = (
    "cloud_processing",
    "proactive_invitations",
    "save_memory",
    "record_observations",
)
SHARE_TOPICS = ("participation", "activities", "mood", "meals", "wellbeing")
CAPABILITY_WITH_TOPIC = "share_topic"


def normalise_capability(capability: str) -> str:
    if capability not in CAPABILITIES and capability != CAPABILITY_WITH_TOPIC:
        raise validation_error(f"Unknown capability: {capability!r}")
    return capability


def storage_key(capability: str, topic: str = "") -> tuple[str, str]:
    """Validate a (capability, topic) pair and return the storage key."""
    normalise_capability(capability)
    if capability == CAPABILITY_WITH_TOPIC:
        if topic not in SHARE_TOPICS:
            raise validation_error(
                f"share_topic requires a known topic, got {topic!r}",
                allowed_topics=list(SHARE_TOPICS),
            )
        return capability, topic
    if topic:
        raise validation_error(f"{capability} does not take a topic")
    return capability, ""


class ConsentService:
    def __init__(self, db: Database, clock: Clock) -> None:
        self.db = db
        self.clock = clock

    # -- state -----------------------------------------------------------
    def _ensure_state(self, senior_id: int) -> int:
        row = self.db.query_one(
            "SELECT version FROM consent_state WHERE senior_id = ?", (senior_id,)
        )
        if row is not None:
            return int(row["version"])
        self.db.execute(
            "INSERT INTO consent_state(senior_id, version) VALUES (?, 1)", (senior_id,)
        )
        return 1

    def version(self, senior_id: int) -> int:
        return self._ensure_state(senior_id)

    def items(self, senior_id: int) -> list[dict[str, Any]]:
        rows = self.db.query(
            "SELECT capability, topic, allowed, version, updated_at FROM consents "
            "WHERE senior_id = ? ORDER BY capability, topic",
            (senior_id,),
        )
        return [
            {
                "capability": row["capability"],
                "topic": row["topic"],
                "allowed": bool(row["allowed"]),
                "version": row["version"],
                "updated_at": row["updated_at"],
            }
            for row in rows
        ]

    def snapshot(self, senior_id: int) -> dict[str, Any]:
        version = self.version(senior_id)
        return {"version": version, "items": self.items(senior_id)}

    # -- queries ---------------------------------------------------------
    def is_allowed(self, senior_id: int, capability: str, topic: str = "") -> bool:
        capability, topic = storage_key(capability, topic)
        row = self.db.query_one(
            "SELECT allowed FROM consents WHERE senior_id = ? AND capability = ? AND topic = ?",
            (senior_id, capability, topic),
        )
        return bool(row and row["allowed"])

    def require(self, senior_id: int, capability: str, topic: str = "") -> None:
        if not self.is_allowed(senior_id, capability, topic):
            raise AppError(
                "consent_required",
                f"Permission for {capability}{':' + topic if topic else ''} has not been given.",
                capability=capability,
                topic=topic or None,
            )

    def allowed_topics(self, senior_id: int) -> list[str]:
        return [topic for topic in SHARE_TOPICS if self.is_allowed(senior_id, "share_topic", topic)]

    # -- mutation ---------------------------------------------------------
    def update(
        self,
        senior_id: int,
        base_version: int,
        changes: Iterable[dict[str, Any]],
        actor_user_id: Optional[int] = None,
    ) -> dict[str, Any]:
        current = self.version(senior_id)
        if int(base_version) != current:
            raise AppError(
                "consent_version_conflict",
                "Permissions changed since you loaded them.",
                current_version=current,
            )
        normalised: list[tuple[str, str, bool]] = []
        for change in changes:
            if not isinstance(change, dict):
                raise validation_error("Each change must be an object.")
            capability = change.get("capability")
            if not isinstance(capability, str):
                raise validation_error("Each change needs a capability.")
            topic = change.get("topic") or ""
            allowed = change.get("allowed")
            if not isinstance(allowed, bool):
                raise validation_error("Each change needs allowed: true/false.")
            key = storage_key(capability, str(topic))
            if key not in [(c, t) for c, t, _ in normalised]:
                normalised.append((key[0], key[1], allowed))
            else:
                normalised = [item for item in normalised if (item[0], item[1]) != key]
                normalised.append((key[0], key[1], allowed))
        if not normalised:
            return self.snapshot(senior_id)

        now = iso_utc(self.clock.now())
        with self.db.tx() as conn:
            effective: list[tuple[str, str, bool]] = []
            for capability, topic, allowed in normalised:
                existing = conn.execute(
                    "SELECT allowed FROM consents WHERE senior_id = ? AND capability = ? "
                    "AND topic = ?",
                    (senior_id, capability, topic),
                ).fetchone()
                if existing is not None and bool(existing["allowed"]) == allowed:
                    continue
                effective.append((capability, topic, allowed))
            if not effective:
                return self.snapshot(senior_id)

            new_version = current + 1
            conn.execute(
                "UPDATE consent_state SET version = ? WHERE senior_id = ?",
                (new_version, senior_id),
            )
            for capability, topic, allowed in effective:
                conn.execute(
                    "INSERT INTO consents(senior_id, capability, topic, allowed, version, updated_at) "
                    "VALUES (?,?,?,?,?,?) "
                    "ON CONFLICT(senior_id, capability, topic) DO UPDATE SET "
                    "allowed = excluded.allowed, version = excluded.version, "
                    "updated_at = excluded.updated_at",
                    (senior_id, capability, topic, 1 if allowed else 0, new_version, now),
                )
                audit.write(
                    self.db,
                    self.clock,
                    actor_user_id,
                    "consent_granted" if allowed else "consent_revoked",
                    "consent",
                    f"{capability}:{topic}" if topic else capability,
                    outcome="allowed" if allowed else "denied",
                )
        return self.snapshot(senior_id)

    def seed(
        self,
        senior_id: int,
        *,
        cloud_processing: bool = False,
        proactive_invitations: bool = False,
        save_memory: bool = False,
        record_observations: bool = False,
        share_topics: Iterable[str] = (),
    ) -> int:
        """Write explicit rows for a new account (seeds/tests, not a user action)."""
        version = self.version(senior_id)
        now = iso_utc(self.clock.now())
        share_topics = set(share_topics)
        rows = [
            ("cloud_processing", "", cloud_processing),
            ("proactive_invitations", "", proactive_invitations),
            ("save_memory", "", save_memory),
            ("record_observations", "", record_observations),
        ]
        rows += [("share_topic", topic, topic in share_topics) for topic in SHARE_TOPICS]
        with self.db.tx() as conn:
            for capability, topic, allowed in rows:
                conn.execute(
                    "INSERT INTO consents(senior_id, capability, topic, allowed, version, updated_at) "
                    "VALUES (?,?,?,?,?,?) "
                    "ON CONFLICT(senior_id, capability, topic) DO NOTHING",
                    (senior_id, capability, topic, 1 if allowed else 0, version, now),
                )
        return version
