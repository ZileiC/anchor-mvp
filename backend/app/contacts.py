"""Saved contacts and recorded call initiations (SPEC §6.6 family bridge).

Calls are ordinary telephone calls. The backend never dials: it resolves an
authorised contact, records that the user started a call and returns the ``tel:``
URI for the device. A dialer opening does not prove the family spoke, so the
optional ``confirmed`` flag records the user's own confirmation separately.

Caregivers may read the linked senior's saved contacts only so the digest's
"Call to check in" button can reach the right person (SPEC §4); they can never
read the other private tables.
"""

from __future__ import annotations

import re
from typing import Any, Optional

from . import audit
from .clock import Clock, iso_utc
from .db import Database
from .errors import AppError, not_found, validation_error
from .relationships import RelationshipService


def contact_public(row: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": int(row["id"]),
        "label": row["label"],
        "phone": row["phone"],
        "is_family": bool(row["is_family"]),
        "created_at": row["created_at"],
    }


def dial_uri(phone: str) -> str:
    digits = re.sub(r"[^0-9+]", "", phone or "")
    return f"tel:{digits}"


class ContactService:
    def __init__(
        self, db: Database, clock: Clock, relationships: Optional[RelationshipService] = None
    ) -> None:
        self.db = db
        self.clock = clock
        self.relationships = relationships or RelationshipService(db, clock)

    def list_for(self, user: dict[str, Any]) -> list[dict[str, Any]]:
        if user["role"] == "senior":
            rows = self.db.query(
                "SELECT * FROM contacts WHERE senior_id = ? ORDER BY id", (int(user["id"]),)
            )
        else:
            link = self.relationships.linked_senior(int(user["id"]))
            if link is None:
                return []
            rows = self.db.query(
                "SELECT * FROM contacts WHERE senior_id = ? ORDER BY id",
                (int(link["senior_id"]),),
            )
        return [contact_public(row) for row in rows]

    def _resolve(self, user: dict[str, Any], contact_id: int) -> dict[str, Any]:
        if user["role"] == "senior":
            row = self.db.query_one(
                "SELECT * FROM contacts WHERE id = ? AND senior_id = ?",
                (int(contact_id), int(user["id"])),
            )
            if row is None:
                raise not_found("Contact not found.")
            return row

        link = self.relationships.linked_senior(int(user["id"]))
        if link is None:
            raise AppError("relationship_inactive", "This family connection is not active.")
        row = self.db.query_one("SELECT * FROM contacts WHERE id = ?", (int(contact_id),))
        if row is None:
            raise not_found("Contact not found.")
        if int(row["senior_id"]) != int(link["senior_id"]):
            raise AppError("caregiver_scope_denied", "That contact belongs to someone else.")
        return row

    def initiate(
        self, user: dict[str, Any], contact_id: int, confirmed: Optional[bool] = None
    ) -> dict[str, Any]:
        contact = self._resolve(user, contact_id)
        if user["role"] == "caregiver":
            # Re-check the accepted link explicitly: _resolve already did, keep it obvious.
            self.relationships.require_active_link(int(user["id"]), int(contact["senior_id"]))
            if confirmed is not None and not isinstance(confirmed, bool):
                raise validation_error("confirmed must be true or false.")

        now_dt = self.clock.now()
        now = iso_utc(now_dt)
        confirmed_at = now if confirmed is True else None
        action_id = self.db.insert(
            "INSERT INTO contact_actions(senior_id, actor_user_id, contact_id, phone, "
            "initiated_at, confirmed_at) VALUES (?,?,?,?,?,?)",
            (
                int(contact["senior_id"]),
                int(user["id"]),
                int(contact["id"]),
                contact["phone"],
                now,
                confirmed_at,
            ),
        )
        audit.write(
            self.db,
            self.clock,
            int(user["id"]),
            "contact_initiated",
            "contact_action",
            action_id,
            outcome="initiated",
        )
        return {
            "contact_action_id": action_id,
            "label": contact["label"],
            "phone": contact["phone"],
            "dial_uri": dial_uri(contact["phone"]),
            "confirmed_at": confirmed_at,
        }


__all__ = ["ContactService", "contact_public", "dial_uri"]
