"""Invitations, family links and caregiver schedule proposals (SPEC §6.1).

Invitations are single-use, hashed at rest and time limited. Accepting one creates
a *pending* link only: sharing additionally requires the senior's approval.
"""

from __future__ import annotations

import hashlib
import json
import secrets
from datetime import datetime, timezone
from typing import Any, Optional

from . import audit
from .clock import Clock, iso_utc, parse_iso
from .db import Database
from .errors import AppError, forbidden, validation_error
from .preferences import PreferencesService, validate_patch
from .providers.notifier import DatabaseNotifier

PROPOSAL_FIELDS = ("greeting_start", "greeting_end", "daily_cap", "paused")
INVITATION_MAX_HOURS = 24 * 14


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


class RelationshipService:
    def __init__(
        self,
        db: Database,
        clock: Clock,
        notifier: Optional[DatabaseNotifier] = None,
    ) -> None:
        self.db = db
        self.clock = clock
        self.notifier = notifier or DatabaseNotifier(db, clock)

    # -- invitations ------------------------------------------------------
    def create_invitation(self, senior_id: int, expires_in_hours: int = 24) -> dict[str, Any]:
        if not isinstance(expires_in_hours, int) or not 1 <= expires_in_hours <= INVITATION_MAX_HOURS:
            raise validation_error(
                f"expires_in_hours must be an integer 1..{INVITATION_MAX_HOURS}"
            )
        now = self.clock.now()
        expires_at = now.timestamp() + expires_in_hours * 3600
        token = secrets.token_urlsafe(32)
        invitation_id = self.db.insert(
            "INSERT INTO invitations(senior_id, token_hash, expires_at, created_at) "
            "VALUES (?,?,?,?)",
            (
                senior_id,
                hash_token(token),
                iso_utc(datetime.fromtimestamp(expires_at, timezone.utc)),
                iso_utc(now),
            ),
        )
        row = self.db.query_one("SELECT * FROM invitations WHERE id = ?", (invitation_id,))
        return {
            "id": row["id"],
            "token": token,
            "expires_at": row["expires_at"],
            "accept_path": "/api/v1/invitations/accept",
        }

    def accept_invitation(self, caregiver_id: int, token: str) -> dict[str, Any]:
        if not isinstance(token, str) or not token.strip():
            raise AppError("invitation_invalid", "This invitation is no longer valid.")
        row = self.db.query_one(
            "SELECT * FROM invitations WHERE token_hash = ?", (hash_token(token.strip()),)
        )
        if row is None or row["used_at"] is not None:
            raise AppError("invitation_invalid", "This invitation is no longer valid.")
        if parse_iso(row["expires_at"]) <= self.clock.now():
            raise AppError("invitation_invalid", "This invitation has expired.")
        now = iso_utc(self.clock.now())
        with self.db.tx() as conn:
            conn.execute(
                "UPDATE invitations SET used_at = ? WHERE id = ? AND used_at IS NULL",
                (now, row["id"]),
            )
            existing = conn.execute(
                "SELECT * FROM relationships WHERE senior_id = ? AND caregiver_id = ?",
                (row["senior_id"], caregiver_id),
            ).fetchone()
            if existing is not None and existing["status"] == "accepted":
                raise AppError("conflict", "You are already connected to this person.")
            if existing is None:
                relationship_id = conn.execute(
                    "INSERT INTO relationships(senior_id, caregiver_id, status, created_at) "
                    "VALUES (?,?, 'pending', ?)",
                    (row["senior_id"], caregiver_id, now),
                ).lastrowid
            else:
                relationship_id = existing["id"]
                conn.execute(
                    "UPDATE relationships SET status = 'pending', created_at = ?, "
                    "accepted_at = NULL, revoked_at = NULL WHERE id = ?",
                    (now, relationship_id),
                )
        return {"relationship_id": int(relationship_id), "status": "pending"}

    # -- relationship lifecycle -------------------------------------------
    def approve(self, relationship_id: int, senior_id: int) -> dict[str, Any]:
        row = self.db.query_one("SELECT * FROM relationships WHERE id = ?", (relationship_id,))
        if row is None or int(row["senior_id"]) != int(senior_id):
            raise AppError("not_found", "Not found.")
        if row["status"] != "pending":
            raise AppError("conflict", "This connection request is no longer pending.")
        now = iso_utc(self.clock.now())
        self.db.execute(
            "UPDATE relationships SET status = 'accepted', accepted_at = ? WHERE id = ?",
            (now, relationship_id),
        )
        self.notifier.notify(int(row["caregiver_id"]), "relationship", "relationship_approved")
        audit.write(
            self.db,
            self.clock,
            senior_id,
            "relationship_approved",
            "relationship",
            relationship_id,
        )
        return self.db.query_one("SELECT * FROM relationships WHERE id = ?", (relationship_id,))

    def revoke(self, relationship_id: int, senior_id: int) -> dict[str, Any]:
        row = self.db.query_one("SELECT * FROM relationships WHERE id = ?", (relationship_id,))
        if row is None or int(row["senior_id"]) != int(senior_id):
            raise forbidden("You can only change your own family connections.")
        if row["status"] == "revoked":
            return {"id": relationship_id, "status": "revoked"}
        now = iso_utc(self.clock.now())
        with self.db.tx() as conn:
            conn.execute(
                "UPDATE relationships SET status = 'revoked', revoked_at = ? WHERE id = ?",
                (now, relationship_id),
            )
            conn.execute(
                "UPDATE digests SET status = 'cancelled', updated_at = ? "
                "WHERE senior_id = ? AND status IN ('draft','awaiting_senior_approval','approved')",
                (now, row["senior_id"]),
            )
            conn.execute(
                "DELETE FROM jobs WHERE job_type = 'notify_digest' AND status IN ('pending','failed') "
                "AND json_extract(payload_json, '$.senior_id') = ?",
                (row["senior_id"],),
            )
            conn.execute(
                "UPDATE schedule_proposals SET status = 'cancelled', decided_at = ? "
                "WHERE senior_id = ? AND status = 'pending'",
                (now, row["senior_id"]),
            )
        audit.write(
            self.db,
            self.clock,
            senior_id,
            "relationship_revoked",
            "relationship",
            relationship_id,
            outcome="revoked",
        )
        return {"id": relationship_id, "status": "revoked"}

    def list_for(self, user: dict[str, Any]) -> list[dict[str, Any]]:
        if user["role"] == "senior":
            rows = self.db.query(
                "SELECT rel.*, u.display_name AS counterpart_name, u.locale AS counterpart_locale "
                "FROM relationships rel JOIN users u ON u.id = rel.caregiver_id "
                "WHERE rel.senior_id = ? ORDER BY rel.id",
                (int(user["id"]),),
            )
            for row in rows:
                row["counterpart_id"] = row["caregiver_id"]
        else:
            rows = self.db.query(
                "SELECT rel.*, u.display_name AS counterpart_name, u.locale AS counterpart_locale "
                "FROM relationships rel JOIN users u ON u.id = rel.senior_id "
                "WHERE rel.caregiver_id = ? ORDER BY rel.id",
                (int(user["id"]),),
            )
            for row in rows:
                row["counterpart_id"] = row["senior_id"]
        return rows

    def linked_senior(self, caregiver_id: int) -> Optional[dict[str, Any]]:
        return self.db.query_one(
            "SELECT * FROM relationships WHERE caregiver_id = ? AND status = 'accepted' "
            "ORDER BY id DESC LIMIT 1",
            (caregiver_id,),
        )

    def require_active_link(self, caregiver_id: int, senior_id: int) -> dict[str, Any]:
        row = self.db.query_one(
            "SELECT * FROM relationships WHERE caregiver_id = ? AND senior_id = ? AND status = 'accepted'",
            (caregiver_id, senior_id),
        )
        if row is None:
            raise AppError("relationship_inactive", "This family connection is not active.")
        return row


class ScheduleProposalService:
    def __init__(self, db: Database, clock: Clock, preferences: PreferencesService) -> None:
        self.db = db
        self.clock = clock
        self.preferences = preferences
        self.relationships = RelationshipService(db, clock)

    def create(self, caregiver_id: int, senior_id: int, payload: dict[str, Any]) -> dict[str, Any]:
        if not isinstance(payload, dict) or not payload:
            raise validation_error("payload must contain at least one proposal.")
        disallowed = [key for key in payload if key not in PROPOSAL_FIELDS]
        if disallowed:
            raise validation_error(
                "Caregivers may propose only the greeting window, daily cap and pause.",
                allowed=list(PROPOSAL_FIELDS),
            )
        normalised = {key: validate_patch({key: value})[key] for key, value in payload.items()}
        self.relationships.require_active_link(caregiver_id, senior_id)
        proposal_id = self.db.insert(
            "INSERT INTO schedule_proposals(senior_id, caregiver_id, payload_json, status, created_at) "
            "VALUES (?,?,?,'pending',?)",
            (
                senior_id,
                caregiver_id,
                json.dumps(normalised, ensure_ascii=False),
                iso_utc(self.clock.now()),
            ),
        )
        return self.db.query_one("SELECT * FROM schedule_proposals WHERE id = ?", (proposal_id,))

    def list_for(self, user: dict[str, Any]) -> list[dict[str, Any]]:
        if user["role"] == "senior":
            rows = self.db.query(
                "SELECT p.*, u.display_name AS counterpart_name FROM schedule_proposals p "
                "JOIN users u ON u.id = p.caregiver_id WHERE p.senior_id = ? ORDER BY p.id",
                (int(user["id"]),),
            )
        else:
            rows = self.db.query(
                "SELECT p.*, u.display_name AS counterpart_name FROM schedule_proposals p "
                "JOIN users u ON u.id = p.senior_id WHERE p.caregiver_id = ? ORDER BY p.id",
                (int(user["id"]),),
            )
        for row in rows:
            row["payload"] = json.loads(row["payload_json"])
        return rows

    def approve(self, proposal_id: int, senior_id: int) -> dict[str, Any]:
        row = self.db.query_one("SELECT * FROM schedule_proposals WHERE id = ?", (proposal_id,))
        if row is None or int(row["senior_id"]) != int(senior_id):
            raise AppError("not_found", "Not found.")
        if row["status"] != "pending":
            raise AppError("conflict", "This proposal has already been decided.")
        payload = json.loads(row["payload_json"])
        self.preferences.patch(senior_id, payload)
        now = iso_utc(self.clock.now())
        self.db.execute(
            "UPDATE schedule_proposals SET status = 'approved', decided_at = ? WHERE id = ?",
            (now, proposal_id),
        )
        audit.write(
            self.db, self.clock, senior_id, "schedule_proposal_approved", "schedule_proposal", proposal_id
        )
        return self.db.query_one("SELECT * FROM schedule_proposals WHERE id = ?", (proposal_id,))
