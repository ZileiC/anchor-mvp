"""Generic notification inbox (SPEC §6.6 / §7 delivery rules).

Notifications carry only "something is ready" wording; the caregiver opens the
authenticated digest to read it. A user may only see and mark their own rows.
"""

from __future__ import annotations

from typing import Any

from .clock import Clock, iso_utc
from .db import Database
from .errors import AppError
from .models import notification_public


class NotificationService:
    def __init__(self, db: Database, clock: Clock) -> None:
        self.db = db
        self.clock = clock

    def list_for(self, user_id: int) -> list[dict[str, Any]]:
        rows = self.db.query(
            "SELECT * FROM notifications WHERE user_id = ? ORDER BY created_at DESC, id DESC",
            (int(user_id),),
        )
        return [notification_public(row) for row in rows]

    def mark_read(self, notification_id: int, user_id: int) -> dict[str, Any]:
        row = self.db.query_one(
            "SELECT * FROM notifications WHERE id = ? AND user_id = ?",
            (int(notification_id), int(user_id)),
        )
        if row is None:
            raise AppError("not_found", "Not found.")
        if row["read_at"] is None:
            self.db.execute(
                "UPDATE notifications SET read_at = ? WHERE id = ?",
                (iso_utc(self.clock.now()), int(notification_id)),
            )
            row = self.db.query_one("SELECT * FROM notifications WHERE id = ?", (int(notification_id),))
        return notification_public(row)


__all__ = ["NotificationService"]
