"""Audit trail writer (SPEC §4: audit every consent change, revocation, approval,
deletion, call initiation and digest delivery).

Audit rows never contain transcript, audio, memory text or digest item text.
"""

from __future__ import annotations

from typing import Any, Optional

from .clock import Clock, iso_utc
from .db import Database


def write(
    db: Database,
    clock: Clock,
    actor_user_id: Optional[int],
    action: str,
    target_type: str,
    target_id: Any = None,
    outcome: str = "ok",
) -> int:
    return db.insert(
        "INSERT INTO audit_events(actor_user_id, action, target_type, target_id, outcome, created_at) "
        "VALUES (?,?,?,?,?,?)",
        (
            actor_user_id,
            action,
            target_type,
            None if target_id is None else str(target_id),
            outcome,
            iso_utc(clock.now()),
        ),
    )
