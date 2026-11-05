"""Data-rights and retention tests (S8, SPEC §6.7, §7 retention).

Deletion is immediate, counts every table it touched, revokes relationships, bumps
the consent version and leaves an audit trail that contains no content. Retention
purges are rule-based and idempotent.
"""

from __future__ import annotations

import json

import pytest

from app.clock import iso_utc
from app.storage import retention
from tests.helpers import (
    headers,
    insert_contact,
    insert_digest,
    insert_job,
    insert_notification,
    insert_observation,
    link_relationship,
    seed_consents,
)


def _seed_personal_data(app, senior, caregiver):
    ctx = app.state.ctx
    link_relationship(app, senior, caregiver, status="accepted")
    ctx.db.execute(
        "INSERT INTO memories(senior_id, fact, approval_state, approved_at, created_at) "
        "VALUES (?,?, 'approved', ?, ?)",
        (senior["id"], "喜欢在阳台种花。", "2026-01-01T00:00:00Z", "2026-01-01T00:00:00Z"),
    )
    observation_id = insert_observation(
        app, senior, topic="mood", event_date="2026-01-02", evidence="今天心情很好。"
    )
    ctx.db.execute(
        "INSERT INTO sessions(id, senior_id, origin, state, cancellation_token, started_at) "
        "VALUES ('sess-1', ?, 'voluntary', 'ended', 'tok', '2026-01-02T00:00:00Z')",
        (senior["id"],),
    )
    ctx.db.execute(
        "INSERT INTO turns(session_id, role, text, created_at) VALUES "
        "('sess-1', 'senior', '今天心情很好', '2026-01-02T00:00:00Z')"
    )
    digest_id = insert_digest(app, senior, status="approved")
    contact_id = insert_contact(app, senior)
    ctx.db.execute(
        "INSERT INTO contact_actions(senior_id, actor_user_id, contact_id, phone, initiated_at) "
        "VALUES (?,?,?,'+8613900001111','2026-01-02T00:00:00Z')",
        (senior["id"], senior["id"], contact_id),
    )
    ctx.db.execute(
        "INSERT INTO checkin_events(senior_id, device_id, local_date, outcome, created_at) "
        "VALUES (?,'senior-tablet','2026-01-02','shown','2026-01-02T00:00:00Z')",
        (senior["id"],),
    )
    insert_job(
        app,
        "weekly_digest",
        {"senior_id": int(senior["id"]), "period_start": "2025-12-29"},
        f"weekly_digest:{int(senior['id'])}:2025-12-29",
    )
    insert_job(
        app,
        "notify_digest",
        {"digest_id": digest_id, "senior_id": int(senior["id"])},
        f"notify_digest:{digest_id}",
    )
    insert_notification(app, senior)
    insert_notification(app, caregiver)
    return {"observation_id": observation_id, "digest_id": digest_id}


def test_s8_delete_removes_personal_data_and_reports_counts(
    client, app, senior, caregiver, senior_token
):
    ids = _seed_personal_data(app, senior, caregiver)
    before = client.get("/api/v1/consents", headers=headers(senior_token)).json()["version"]

    response = client.request(
        "DELETE", "/api/v1/data", json={"confirm": True}, headers=headers(senior_token)
    )
    assert response.status_code == 200, response.text
    deleted = response.json()["deleted"]
    for table in (
        "memories",
        "observations",
        "sessions",
        "turns",
        "digests",
        "contact_actions",
        "checkin_events",
    ):
        assert table in deleted, deleted
        assert deleted[table] >= 1, (table, deleted)

    db = app.state.ctx.db
    for table in (
        "memories",
        "observations",
        "sessions",
        "turns",
        "digests",
        "contact_actions",
        "checkin_events",
        "jobs",
        "notifications",
    ):
        assert db.query(f"SELECT * FROM {table}") == [], table

    link = db.query_one("SELECT * FROM relationships WHERE senior_id = ?", (senior["id"],))
    assert link["status"] == "revoked"
    assert link["revoked_at"] is not None

    after = client.get("/api/v1/consents", headers=headers(senior_token)).json()["version"]
    assert after > before

    audit = db.query("SELECT * FROM audit_events WHERE action = 'data_deleted'")
    assert len(audit) == 1
    assert audit[0]["target_type"] == "senior"
    assert str(senior["id"]) == audit[0]["target_id"]
    stored = json.dumps(db.query("SELECT * FROM audit_events"), ensure_ascii=False)
    for secret in ("喜欢在阳台种花", "今天心情很好", "+8613900001111"):
        assert secret not in stored


def test_s8_delete_requires_confirm_true(client, app, senior, senior_token):
    first = client.request(
        "DELETE", "/api/v1/data", json={"confirm": False}, headers=headers(senior_token)
    )
    assert first.status_code == 422
    assert first.json()["error"]["code"] == "validation_error"
    second = client.request("DELETE", "/api/v1/data", json={}, headers=headers(senior_token))
    assert second.status_code == 422


def test_s8_delete_requires_senior_and_token(client, caregiver, caregiver_token):
    as_caregiver = client.request(
        "DELETE", "/api/v1/data", json={"confirm": True}, headers=headers(caregiver_token)
    )
    assert as_caregiver.status_code == 403
    assert as_caregiver.json()["error"]["code"] == "forbidden"

    anonymous = client.request("DELETE", "/api/v1/data", json={"confirm": True})
    assert anonymous.status_code == 401
    assert anonymous.json()["error"]["code"] == "unauthorized"


def test_s8_delete_is_scoped_to_the_requesting_senior(
    client, app, make_user, senior, caregiver, senior_token
):
    _seed_personal_data(app, senior, caregiver)
    other = make_user("senior", display_name="别人")
    other_caregiver = make_user("caregiver", display_name="别人家属")
    link_relationship(app, other, other_caregiver, status="accepted")
    insert_observation(app, other, topic="mood", event_date="2026-01-02", evidence="别人的话")
    insert_digest(app, other, status="approved", period_start="2026-01-05")

    response = client.request(
        "DELETE", "/api/v1/data", json={"confirm": True}, headers=headers(senior_token)
    )
    assert response.status_code == 200

    db = app.state.ctx.db
    assert db.scalar(
        "SELECT COUNT(*) AS n FROM observations WHERE senior_id = ?", (other["id"],)
    ) == 1
    assert db.scalar(
        "SELECT COUNT(*) AS n FROM digests WHERE senior_id = ?", (other["id"],)
    ) == 1
    still = db.query_one("SELECT status FROM relationships WHERE senior_id = ?", (other["id"],))
    assert still["status"] == "accepted"


def test_s8_delete_revokes_access_immediately(
    client, app, senior, caregiver, linked, senior_token, caregiver_token
):
    seed_consents(app, senior, record_observations=True, share_topics=("mood",))
    insert_digest(app, senior, status="approved")
    assert client.get("/api/v1/digests", headers=headers(caregiver_token)).status_code == 200

    client.request(
        "DELETE", "/api/v1/data", json={"confirm": True}, headers=headers(senior_token)
    )
    after = client.get("/api/v1/digests", headers=headers(caregiver_token))
    assert after.status_code == 200
    assert after.json()["items"] == []
    assert after.json()["note"] == "insufficient_information"


# -- retention ------------------------------------------------------------
def test_retention_purges_observations_older_than_35_days(app, senior):
    ctx = app.state.ctx
    old = insert_observation(app, senior, topic="mood", event_date="2025-11-20")
    recent = insert_observation(app, senior, topic="mood", event_date="2026-01-02")

    counts = retention.purge_all(ctx.db, ctx.clock)
    assert counts["observations"] == 1
    ids = {row["id"] for row in ctx.db.query("SELECT id FROM observations")}
    assert old not in ids
    assert recent in ids

    again = retention.purge_all(ctx.db, ctx.clock)
    assert again == {"observations": 0, "digests": 0, "notifications": 0, "audit_events": 0}


def test_retention_purges_digests_and_their_notifications(client, app, senior, caregiver, senior_token):
    ctx = app.state.ctx
    client.patch(
        "/api/v1/preferences", json={"digest_retention_days": 30}, headers=headers(senior_token)
    )
    link_relationship(app, senior, caregiver, status="accepted")
    stale = insert_digest(app, senior, status="delivered", period_start="2025-11-01")
    fresh = insert_digest(app, senior, status="delivered", period_start="2026-01-05")
    ctx.db.execute(
        "UPDATE digests SET created_at = '2025-11-01T00:00:00Z' WHERE id = ?", (stale,)
    )
    notification = insert_notification(app, caregiver, kind="digest_ready")
    ctx.db.execute(
        "UPDATE notifications SET created_at = '2025-11-01T00:00:00Z' WHERE id = ?",
        (notification,),
    )

    counts = retention.purge_all(ctx.db, ctx.clock)
    assert counts["digests"] == 1
    assert counts["notifications"] == 1
    ids = {row["id"] for row in ctx.db.query("SELECT id FROM digests")}
    assert stale not in ids
    assert fresh in ids
    assert ctx.db.query("SELECT * FROM notifications WHERE id = ?", (notification,)) == []


def test_retention_purges_audit_after_180_days(app):
    ctx = app.state.ctx
    old = ctx.db.insert(
        "INSERT INTO audit_events(actor_user_id, action, target_type, target_id, outcome, "
        "created_at) VALUES (1,'old_action','x','1','ok','2025-01-01T00:00:00Z')"
    )
    recent = ctx.db.insert(
        "INSERT INTO audit_events(actor_user_id, action, target_type, target_id, outcome, "
        "created_at) VALUES (1,'recent_action','x','1','ok',?)",
        (iso_utc(ctx.clock.now()),),
    )
    counts = retention.purge_all(ctx.db, ctx.clock)
    assert counts["audit_events"] == 1
    ids = {row["id"] for row in ctx.db.query("SELECT id FROM audit_events")}
    assert old not in ids
    assert recent in ids


def test_retention_keeps_approved_memories_until_deleted(app, senior):
    ctx = app.state.ctx
    ctx.db.execute(
        "INSERT INTO memories(senior_id, fact, approval_state, approved_at, created_at) "
        "VALUES (?,?, 'approved', '2020-01-01T00:00:00Z', '2020-01-01T00:00:00Z')",
        (senior["id"], "很旧但经批准的记忆。"),
    )
    retention.purge_all(ctx.db, ctx.clock)
    assert ctx.db.scalar("SELECT COUNT(*) AS n FROM memories") == 1


def test_retention_is_idempotent_and_repeatable(app, senior, caregiver):
    ctx = app.state.ctx
    insert_observation(app, senior, topic="mood", event_date="2025-11-20")
    link_relationship(app, senior, caregiver, status="accepted")
    insert_notification(app, caregiver, kind="digest_ready")
    first = retention.purge_all(ctx.db, ctx.clock)
    second = retention.purge_all(ctx.db, ctx.clock)
    assert first["observations"] == 1
    assert second == {"observations": 0, "digests": 0, "notifications": 0, "audit_events": 0}
