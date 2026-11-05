"""Worker tests: lease claim, retry/backoff/dead, idempotency, retention (SPEC §8)."""

from __future__ import annotations

import json
from datetime import timedelta

from app.clock import iso_utc, parse_iso
from app.jobs import JobRunner, enqueue_due_jobs
from app.main import create_app
from app.worker import main as worker_main
from tests.helpers import (
    DIGEST_PERIOD_START,
    insert_digest,
    insert_job,
    insert_observation,
    link_relationship,
    seed_adequate_observations,
    seed_consents,
)

ALL_TOPICS = ("participation", "activities", "mood", "meals", "wellbeing")


def _run_once(app):
    return JobRunner(app.state.ctx).run_once()


def _digests(app):
    return app.state.ctx.db.query("SELECT * FROM digests ORDER BY id")


# -- scheduling -----------------------------------------------------------
def test_worker_enqueues_previous_local_week_once(app, senior):
    first = enqueue_due_jobs(app.state.ctx)
    assert first["weekly_digest"] == 1
    second = enqueue_due_jobs(app.state.ctx)
    assert second["weekly_digest"] == 0

    jobs = app.state.ctx.db.query("SELECT * FROM jobs WHERE job_type = 'weekly_digest'")
    assert len(jobs) == 1
    assert jobs[0]["idempotency_key"] == f"weekly_digest:{senior['id']}:{DIGEST_PERIOD_START}"
    payload = json.loads(jobs[0]["payload_json"])
    assert payload["period_start"] == "2025-12-29"
    assert payload["period_end"] == "2026-01-05"


def test_worker_cli_seed_and_once(tmp_path, capsys):
    db_path = str(tmp_path / "worker-cli.db")
    assert worker_main(["--seed-jobs", "--db", db_path]) == 0
    seeded = capsys.readouterr().out
    assert "retention_purge" in seeded

    assert worker_main(["--once", "--db", db_path]) == 0
    ran = capsys.readouterr().out
    assert "executed" in ran


# -- required failure test ----------------------------------------------
def failure_worker_restart(
    app, settings, fake_clock, senior, caregiver, linked
):
    """A worker restart must not duplicate a digest or a delivery notification."""
    seed_consents(app, senior, record_observations=True, share_topics=ALL_TOPICS)
    seed_adequate_observations(app, senior, topic="mood")

    enqueue_due_jobs(app.state.ctx)
    _run_once(app)
    digests = _digests(app)
    assert len(digests) == 1
    assert digests[0]["status"] == "draft"

    # Approve through the service: the notify job is now queued.
    digest = app.state.ctx.digests.ensure_weekly_digest(
        int(senior["id"]), "2025-12-29", "2026-01-05"
    )
    app.state.ctx.digests.patch(digest["id"], int(senior["id"]), digest["items"])
    app.state.ctx.digests.approve(digest["id"], int(senior["id"]))
    _run_once(app)

    notifications = app.state.ctx.db.query(
        "SELECT * FROM notifications WHERE user_id = ? AND kind = 'digest_ready'",
        (caregiver["id"],),
    )
    assert len(notifications) == 1

    # "Restart": a fresh application context over the same database file.
    restarted = create_app(settings, clock=fake_clock)
    try:
        enqueue_due_jobs(restarted.state.ctx)
        JobRunner(restarted.state.ctx).run_once()
        JobRunner(restarted.state.ctx).run_once()

        db = restarted.state.ctx.db
        digests = db.query("SELECT * FROM digests")
        assert len(digests) == 1
        assert digests[0]["status"] == "delivered"
        assert len(db.query("SELECT * FROM jobs WHERE job_type = 'weekly_digest'")) == 1
        assert (
            len(
                db.query(
                    "SELECT * FROM notifications WHERE user_id = ? AND kind = 'digest_ready'",
                    (caregiver["id"],),
                )
            )
            == 1
        )
    finally:
        restarted.state.db.close()


def test_worker_retry_backoff_then_dead_letter(app):
    ctx = app.state.ctx
    job_id = insert_job(app, "not_a_job", {"senior_id": 1}, "unknown-job:1")
    ctx.db.execute("UPDATE jobs SET max_attempts = 2 WHERE id = ?", (job_id,))

    results = _run_once(app)
    assert results[0]["status"] == "failed"
    row = ctx.db.query_one("SELECT * FROM jobs WHERE id = ?", (job_id,))
    assert row["attempts"] == 1
    assert row["last_error"] and "unknown job type" in row["last_error"]
    assert parse_iso(row["due_at"]) == ctx.clock.now() + timedelta(minutes=2)

    # Not due yet: a second pass claims nothing.
    assert _run_once(app) == []

    ctx.clock.advance(minutes=3)
    _run_once(app)
    row = ctx.db.query_one("SELECT * FROM jobs WHERE id = ?", (job_id,))
    assert row["status"] == "dead"
    assert row["attempts"] == 2

    ctx.clock.advance(days=1)
    assert _run_once(app) == []


def test_worker_reclaims_an_expired_lease_exactly_once(app, senior):
    ctx = app.state.ctx
    seed_consents(app, senior, record_observations=True, share_topics=ALL_TOPICS)
    job_id = insert_job(
        app,
        "weekly_digest",
        {"senior_id": int(senior["id"]), "period_start": "2025-12-29", "period_end": "2026-01-05"},
        f"weekly_digest:{int(senior['id'])}:2025-12-29",
    )
    past = iso_utc(ctx.clock.now() - timedelta(minutes=5))
    ctx.db.execute(
        "UPDATE jobs SET status = 'running', attempts = 1, lease_expires_at = ? WHERE id = ?",
        (past, job_id),
    )

    results = _run_once(app)
    assert any(item["job_id"] == job_id and item["status"] == "done" for item in results)
    row = ctx.db.query_one("SELECT * FROM jobs WHERE id = ?", (job_id,))
    assert row["status"] == "done"
    assert row["attempts"] == 2
    assert len(_digests(app)) == 1

    # A second pass neither re-runs the job nor duplicates the digest.
    assert _run_once(app) == []
    assert len(_digests(app)) == 1


def test_worker_notify_skips_digest_that_is_not_approved(app, senior):
    ctx = app.state.ctx
    digest_id = insert_digest(app, senior, status="draft")
    insert_job(
        app,
        "notify_digest",
        {"digest_id": digest_id, "senior_id": int(senior["id"])},
        f"notify_digest:{digest_id}",
    )
    results = _run_once(app)
    assert results[0]["status"] == "done"
    assert results[0]["result"]["delivered"] is False
    assert ctx.db.query("SELECT * FROM notifications") == []
    row = ctx.db.query_one("SELECT * FROM digests WHERE id = ?", (digest_id,))
    assert row["status"] == "draft"


def test_worker_notify_cancels_when_relationship_is_not_active(app, senior, caregiver):
    ctx = app.state.ctx
    link_relationship(app, senior, caregiver, status="pending")
    digest_id = insert_digest(app, senior, status="approved")
    insert_job(
        app,
        "notify_digest",
        {"digest_id": digest_id, "senior_id": int(senior["id"])},
        f"notify_digest:{digest_id}",
    )
    _run_once(app)
    row = ctx.db.query_one("SELECT * FROM digests WHERE id = ?", (digest_id,))
    assert row["status"] == "cancelled"
    assert ctx.db.query("SELECT * FROM notifications WHERE kind = 'digest_ready'") == []


def test_worker_notify_happens_once_per_digest(app, senior, caregiver, linked):
    seed_consents(app, senior, record_observations=True, share_topics=ALL_TOPICS)
    seed_adequate_observations(app, senior, topic="mood")
    digest = app.state.ctx.digests.ensure_weekly_digest(
        int(senior["id"]), "2025-12-29", "2026-01-05"
    )
    app.state.ctx.digests.patch(digest["id"], int(senior["id"]), digest["items"])
    approved = app.state.ctx.digests.approve(digest["id"], int(senior["id"]))
    assert approved["status"] == "approved"

    _run_once(app)
    _run_once(app)
    assert len(app.state.ctx.db.query("SELECT * FROM notifications WHERE kind = 'digest_ready'")) == 1
    row = app.state.ctx.db.query_one("SELECT * FROM digests WHERE id = ?", (digest["id"],))
    assert row["status"] == "delivered"
    assert row["delivered_at"] is not None


def test_worker_retention_purge_job_is_idempotent(app, senior):
    ctx = app.state.ctx
    old_id = insert_observation(app, senior, topic="mood", event_date="2025-11-20")
    new_id = insert_observation(app, senior, topic="mood", event_date="2026-01-03")
    insert_job(app, "retention_purge", {}, "retention_purge:manual")

    _run_once(app)
    ids = {
        int(row["id"])
        for row in ctx.db.query("SELECT id FROM observations WHERE senior_id = ?", (senior["id"],))
    }
    assert old_id not in ids
    assert new_id in ids

    from app.storage import retention

    counts = retention.purge_all(ctx.db, ctx.clock)
    assert counts["observations"] == 0
    assert counts["digests"] == 0


# SPEC §10 names this test exactly ``failure_worker_restart``; expose a collectable alias.
test_failure_worker_restart = failure_worker_restart
