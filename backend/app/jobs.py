"""Persistent job queue: claim with a lease, retry with backoff, dead-letter.

SPEC §8:

* claim inside ``BEGIN IMMEDIATE``, mark ``running``, bump ``attempts`` and set
  ``lease_expires_at``;
* success -> ``done``; an error -> ``failed`` with a ``2 ** attempts`` minute
  backoff, and ``dead`` once ``attempts >= max_attempts``;
* a job left ``running`` by a crashed worker is recovered once its lease expires
  and can then be claimed exactly once more (``recover_expired_leases``);
* ``weekly_digest`` is keyed by ``weekly_digest:{senior_id}:{period_start}`` and
  ``notify_digest`` by ``notify_digest:{digest_id}``, so a restart cannot duplicate
  a digest or a notification.

Due-job scheduling lives in :func:`enqueue_due_jobs` and is separate from the
claim loop so ``--once`` can be used in demos and tests without a timer.
"""

from __future__ import annotations

import json
from datetime import datetime, time, timedelta, timezone
from typing import Any, Callable, Optional
from zoneinfo import ZoneInfo

from .clock import Clock, iso_utc, local_date_str, local_now
from .context import AppContext
from .db import Database
from .storage import retention

CLAIMABLE_STATUSES = ("pending", "failed")
JOB_TYPES = ("weekly_digest", "notify_digest", "retention_purge")
MAX_ERROR_LENGTH = 500
WEEKLY_DIGEST_HOUR = 9


# -- queue primitives -----------------------------------------------------
def recover_expired_leases(db: Database, clock: Clock) -> int:
    """Return crashed ``running`` jobs to the retry queue once their lease is over."""
    now = iso_utc(clock.now())
    cursor = db.execute(
        "UPDATE jobs SET status = 'failed', lease_expires_at = NULL, "
        "last_error = COALESCE(last_error, 'lease_expired'), updated_at = ? "
        "WHERE status = 'running' AND lease_expires_at IS NOT NULL AND lease_expires_at < ?",
        (now, now),
    )
    return max(cursor.rowcount, 0)


def claim_job(
    db: Database, clock: Clock, lease_seconds: int
) -> Optional[dict[str, Any]]:
    now_dt = clock.now()
    now = iso_utc(now_dt)
    lease_expires = iso_utc(now_dt + timedelta(seconds=max(1, int(lease_seconds))))
    with db.tx() as conn:
        row = conn.execute(
            "SELECT * FROM jobs WHERE status IN ('pending','failed') AND due_at <= ? "
            "AND (lease_expires_at IS NULL OR lease_expires_at < ?) "
            "ORDER BY due_at, id LIMIT 1",
            (now, now),
        ).fetchone()
        if row is None:
            return None
        conn.execute(
            "UPDATE jobs SET status = 'running', attempts = attempts + 1, "
            "lease_expires_at = ?, updated_at = ? WHERE id = ?",
            (lease_expires, now, row["id"]),
        )
        claimed = conn.execute("SELECT * FROM jobs WHERE id = ?", (row["id"],)).fetchone()
        return dict(claimed)


def finish_job(
    db: Database, clock: Clock, job_id: int, error: Optional[str] = None
) -> Optional[dict[str, Any]]:
    row = db.query_one("SELECT * FROM jobs WHERE id = ?", (int(job_id),))
    if row is None:
        return None
    now_dt = clock.now()
    now = iso_utc(now_dt)
    if error is None:
        db.execute(
            "UPDATE jobs SET status = 'done', lease_expires_at = NULL, last_error = NULL, "
            "updated_at = ? WHERE id = ?",
            (now, int(job_id)),
        )
    else:
        attempts = int(row["attempts"])
        if attempts >= int(row["max_attempts"]):
            db.execute(
                "UPDATE jobs SET status = 'dead', lease_expires_at = NULL, last_error = ?, "
                "updated_at = ? WHERE id = ?",
                (error[:MAX_ERROR_LENGTH], now, int(job_id)),
            )
        else:
            backoff_minutes = 2 ** min(attempts, 20)
            due_at = iso_utc(now_dt + timedelta(minutes=backoff_minutes))
            db.execute(
                "UPDATE jobs SET status = 'failed', lease_expires_at = NULL, last_error = ?, "
                "due_at = ?, updated_at = ? WHERE id = ?",
                (error[:MAX_ERROR_LENGTH], due_at, now, int(job_id)),
            )
    return db.query_one("SELECT * FROM jobs WHERE id = ?", (int(job_id),))


def enqueue_job(
    db: Database,
    clock: Clock,
    job_type: str,
    payload: dict[str, Any],
    idempotency_key: str,
    *,
    due_at: Optional[str] = None,
    max_attempts: int = 5,
) -> Optional[int]:
    """Insert a job once; returns ``None`` when the idempotency key already exists."""
    now = iso_utc(clock.now())
    with db.tx() as conn:
        cursor = conn.execute(
            "INSERT OR IGNORE INTO jobs(job_type, payload_json, due_at, status, max_attempts, "
            "idempotency_key, created_at, updated_at) VALUES (?,?,?, 'pending', ?, ?, ?, ?)",
            (
                job_type,
                json.dumps(payload, ensure_ascii=False),
                due_at or now,
                int(max_attempts),
                idempotency_key,
                now,
                now,
            ),
        )
        if cursor.rowcount == 0:
            return None
        return int(cursor.lastrowid or 0)


# -- scheduling -----------------------------------------------------------
def _weekly_period(clock: Clock, timezone_name: str) -> tuple[str, str, datetime]:
    """Previous ISO week (local) and the UTC moment its digest is due."""
    local = local_now(clock.now(), timezone_name)
    this_monday = local.date() - timedelta(days=local.weekday())
    try:
        zone = ZoneInfo(timezone_name)
    except Exception:  # pragma: no cover - stored timezones are validated upstream
        zone = ZoneInfo("Asia/Shanghai")
    due_local = datetime.combine(this_monday, time(hour=WEEKLY_DIGEST_HOUR), tzinfo=zone)
    return (
        (this_monday - timedelta(days=7)).isoformat(),
        this_monday.isoformat(),
        due_local.astimezone(timezone.utc),
    )


def enqueue_due_jobs(ctx: AppContext) -> dict[str, int]:
    """Queue this week's digests and today's retention purge (idempotent)."""
    db = ctx.db
    clock = ctx.clock
    now = clock.now()
    enqueued = {"weekly_digest": 0, "retention_purge": 0}

    for senior in db.query("SELECT id, timezone FROM users WHERE role = 'senior' ORDER BY id"):
        period_start, period_end, due_at = _weekly_period(clock, senior["timezone"])
        if now < due_at:
            continue
        job_id = enqueue_job(
            db,
            clock,
            "weekly_digest",
            {
                "senior_id": int(senior["id"]),
                "period_start": period_start,
                "period_end": period_end,
            },
            f"weekly_digest:{int(senior['id'])}:{period_start}",
            due_at=iso_utc(due_at),
        )
        if job_id is not None:
            enqueued["weekly_digest"] += 1

    local_today = local_date_str(clock, ctx.settings.timezone)
    if (
        enqueue_job(
            db,
            clock,
            "retention_purge",
            {},
            f"retention_purge:{local_today}",
            due_at=iso_utc(now),
        )
        is not None
    ):
        enqueued["retention_purge"] += 1
    return enqueued


# -- execution ------------------------------------------------------------
class JobRunner:
    """Runs already-enqueued jobs; scheduling is done by :func:`enqueue_due_jobs`."""

    def __init__(self, ctx: AppContext, lease_seconds: Optional[int] = None) -> None:
        self.ctx = ctx
        self.lease_seconds = int(lease_seconds or ctx.settings.job_lease_seconds)
        self.handlers: dict[str, Callable[[dict[str, Any]], Any]] = {
            "weekly_digest": self._weekly_digest,
            "notify_digest": self._notify_digest,
            "retention_purge": self._retention_purge,
        }

    def _payload(self, job: dict[str, Any]) -> dict[str, Any]:
        try:
            payload = json.loads(job["payload_json"] or "{}")
        except (TypeError, ValueError):
            return {}
        return payload if isinstance(payload, dict) else {}

    def _weekly_digest(self, job: dict[str, Any]) -> dict[str, Any]:
        payload = self._payload(job)
        digest = self.ctx.digests.ensure_weekly_digest(
            int(payload["senior_id"]),
            str(payload["period_start"]),
            str(payload["period_end"]),
        )
        return {"digest_id": digest["id"], "status": digest["status"]}

    def _notify_digest(self, job: dict[str, Any]) -> dict[str, Any]:
        payload = self._payload(job)
        return self.ctx.digests.deliver(int(payload["digest_id"]))

    def _retention_purge(self, _: dict[str, Any]) -> dict[str, int]:
        return retention.purge_all(self.ctx.db, self.ctx.clock)

    def run_once(self, limit: int = 100) -> list[dict[str, Any]]:
        recover_expired_leases(self.ctx.db, self.ctx.clock)
        results: list[dict[str, Any]] = []
        for _ in range(max(1, int(limit))):
            job = claim_job(self.ctx.db, self.ctx.clock, self.lease_seconds)
            if job is None:
                break
            handler = self.handlers.get(str(job["job_type"]))
            try:
                if handler is None:
                    raise RuntimeError(f"unknown job type: {job['job_type']}")
                detail = handler(job)
            except Exception as exc:  # noqa: BLE001 - a job failure must not kill the worker
                finished = finish_job(self.ctx.db, self.ctx.clock, int(job["id"]), str(exc))
                results.append(
                    {
                        "job_id": int(job["id"]),
                        "job_type": job["job_type"],
                        "status": finished["status"] if finished else "unknown",
                        "error": str(exc)[:MAX_ERROR_LENGTH],
                    }
                )
            else:
                finish_job(self.ctx.db, self.ctx.clock, int(job["id"]))
                results.append(
                    {
                        "job_id": int(job["id"]),
                        "job_type": job["job_type"],
                        "status": "done",
                        "result": detail,
                    }
                )
        return results


__all__ = [
    "CLAIMABLE_STATUSES",
    "JOB_TYPES",
    "JobRunner",
    "claim_job",
    "enqueue_due_jobs",
    "enqueue_job",
    "finish_job",
    "recover_expired_leases",
]
