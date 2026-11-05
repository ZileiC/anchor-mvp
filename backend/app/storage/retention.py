"""Retention rules and the data-deletion request (SPEC §7 retention, §6.7, §8).

Two entry points:

* :class:`RetentionService` purges observations older than 35 days, digests past
  each senior's ``digest_retention_days`` and audit rows older than 180 days.
  Every rule is idempotent: running the purge twice deletes nothing the second
  time.
* :func:`delete_senior_data` implements the older adult's immediate deletion
  request. It removes content, cancels queued jobs, revokes relationships and
  bumps the consent version. Audit rows written here never contain content.

Notifications are generic by design (SPEC §6.6), so purging them with the digest
they announced leaks nothing.
"""

from __future__ import annotations

from datetime import timedelta
from typing import Any

from .. import audit
from ..clock import Clock, iso_utc, local_now
from ..db import Database

OBSERVATION_RETENTION_DAYS = 35
AUDIT_RETENTION_DAYS = 180
DEFAULT_DIGEST_RETENTION_DAYS = 365
PERSONAL_TABLES = (
    "memories",
    "observations",
    "sessions",
    "digests",
    "contact_actions",
    "checkin_events",
)


def _seniors(db: Database) -> list[dict[str, Any]]:
    return db.query("SELECT id, timezone FROM users WHERE role = 'senior' ORDER BY id")


def purge_observations(db: Database, clock: Clock) -> int:
    """Delete observations whose local ``event_date`` is older than 35 days."""
    removed = 0
    for senior in _seniors(db):
        local_today = local_now(clock.now(), senior["timezone"]).date()
        cutoff = (local_today - timedelta(days=OBSERVATION_RETENTION_DAYS)).isoformat()
        cursor = db.execute(
            "DELETE FROM observations WHERE senior_id = ? AND event_date < ?",
            (int(senior["id"]), cutoff),
        )
        removed += max(cursor.rowcount, 0)
    return removed


def purge_digests(db: Database, clock: Clock) -> tuple[int, int]:
    """Delete digests past ``digest_retention_days`` and their generic notifications."""
    digests_removed = 0
    notifications_removed = 0
    for senior in _seniors(db):
        senior_id = int(senior["id"])
        prefs = db.query_one(
            "SELECT digest_retention_days FROM preferences WHERE senior_id = ?", (senior_id,)
        )
        days = int(prefs["digest_retention_days"]) if prefs else DEFAULT_DIGEST_RETENTION_DAYS
        cutoff = iso_utc(clock.now() - timedelta(days=days))
        stale = db.query(
            "SELECT id FROM digests WHERE senior_id = ? AND created_at < ?", (senior_id, cutoff)
        )
        if not stale:
            continue
        db.execute(
            "DELETE FROM digests WHERE senior_id = ? AND created_at < ?", (senior_id, cutoff)
        )
        digests_removed += len(stale)

        caregivers = db.query(
            "SELECT DISTINCT caregiver_id FROM relationships WHERE senior_id = ?", (senior_id,)
        )
        for row in caregivers:
            cursor = db.execute(
                "DELETE FROM notifications WHERE user_id = ? AND kind = 'digest_ready' "
                "AND created_at < ?",
                (int(row["caregiver_id"]), cutoff),
            )
            notifications_removed += max(cursor.rowcount, 0)
    return digests_removed, notifications_removed


def purge_audit(db: Database, clock: Clock) -> int:
    cutoff = iso_utc(clock.now() - timedelta(days=AUDIT_RETENTION_DAYS))
    cursor = db.execute("DELETE FROM audit_events WHERE created_at < ?", (cutoff,))
    return max(cursor.rowcount, 0)


def purge_all(db: Database, clock: Clock) -> dict[str, int]:
    """Run every retention rule; safe to call repeatedly."""
    digests, notifications = purge_digests(db, clock)
    return {
        "observations": purge_observations(db, clock),
        "digests": digests,
        "notifications": notifications,
        "audit_events": purge_audit(db, clock),
    }


class RetentionService:
    def __init__(self, db: Database, clock: Clock) -> None:
        self.db = db
        self.clock = clock

    def purge_all(self) -> dict[str, int]:
        return purge_all(self.db, self.clock)


def _placeholders(count: int) -> str:
    return ",".join("?" for _ in range(count))


def delete_senior_data(db: Database, clock: Clock, senior_id: int) -> dict[str, int]:
    """Immediately remove an older adult's personal data (SPEC §6.7).

    Returns a per-table count of deleted rows. The only audit row written names
    the action and the account, never the deleted content.
    """
    senior_id = int(senior_id)
    now = iso_utc(clock.now())
    counts: dict[str, int] = {}

    with db.tx() as conn:
        caregiver_rows = conn.execute(
            "SELECT DISTINCT caregiver_id FROM relationships WHERE senior_id = ?", (senior_id,)
        ).fetchall()
        notification_users = [senior_id] + [int(row["caregiver_id"]) for row in caregiver_rows]

        cursor = conn.execute(
            "DELETE FROM turns WHERE session_id IN (SELECT id FROM sessions WHERE senior_id = ?)",
            (senior_id,),
        )
        counts["turns"] = max(cursor.rowcount, 0)

        for table in PERSONAL_TABLES:
            cursor = conn.execute(f"DELETE FROM {table} WHERE senior_id = ?", (senior_id,))
            counts[table] = max(cursor.rowcount, 0)

        cursor = conn.execute(
            "DELETE FROM jobs WHERE status IN ('pending','failed','running') "
            "AND (json_extract(payload_json, '$.senior_id') = ? OR idempotency_key LIKE ?)",
            (senior_id, f"weekly_digest:{senior_id}:%"),
        )
        counts["jobs"] = max(cursor.rowcount, 0)

        cursor = conn.execute(
            f"DELETE FROM notifications WHERE user_id IN ({_placeholders(len(notification_users))})",
            notification_users,
        )
        counts["notifications"] = max(cursor.rowcount, 0)

        cursor = conn.execute(
            "UPDATE relationships SET status = 'revoked', revoked_at = ? "
            "WHERE senior_id = ? AND status != 'revoked'",
            (now, senior_id),
        )
        counts["relationships_revoked"] = max(cursor.rowcount, 0)

        conn.execute(
            "INSERT INTO consent_state(senior_id, version) VALUES (?, 1) "
            "ON CONFLICT(senior_id) DO UPDATE SET version = version + 1",
            (senior_id,),
        )
        counts["consent_version_bumped"] = 1

    audit.write(db, clock, senior_id, "data_deleted", "senior", senior_id, outcome="deleted")
    return counts


class DataRightsService:
    def __init__(self, db: Database, clock: Clock) -> None:
        self.db = db
        self.clock = clock

    def delete(self, senior_id: int) -> dict[str, int]:
        return delete_senior_data(self.db, self.clock, senior_id)


__all__ = [
    "AUDIT_RETENTION_DAYS",
    "DataRightsService",
    "OBSERVATION_RETENTION_DAYS",
    "RetentionService",
    "delete_senior_data",
    "purge_all",
    "purge_audit",
    "purge_digests",
    "purge_observations",
]
