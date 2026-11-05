"""Schema migration, transaction and constraint behaviour (SPEC §3)."""

from __future__ import annotations

import sqlite3

import pytest

from app.db import Database

EXPECTED_TABLES = {
    "users",
    "relationships",
    "invitations",
    "preferences",
    "consents",
    "consent_state",
    "memories",
    "contacts",
    "sessions",
    "turns",
    "observations",
    "activity_rotation",
    "digests",
    "jobs",
    "schedule_proposals",
    "contact_actions",
    "checkin_events",
    "notifications",
    "audit_events",
}


def _tables(db: Database) -> set[str]:
    rows = db.query("SELECT name FROM sqlite_master WHERE type='table'")
    return {row["name"] for row in rows}


def test_migrate_creates_every_table(tmp_path):
    db = Database(tmp_path / "anchor.db")
    applied = db.migrate()
    assert "001_init.sql" in applied
    tables = _tables(db)
    missing = EXPECTED_TABLES - tables
    assert not missing, f"missing tables: {sorted(missing)}"
    db.close()


def test_migrate_is_idempotent(tmp_path):
    db = Database(tmp_path / "anchor.db")
    db.migrate()
    assert db.migrate() == []
    db.close()


def test_foreign_keys_are_enforced(tmp_path):
    db = Database(tmp_path / "anchor.db")
    db.migrate()
    with pytest.raises(sqlite3.IntegrityError):
        db.execute(
            "INSERT INTO relationships(senior_id, caregiver_id, status, created_at) "
            "VALUES (999, 998, 'pending', '2026-01-01T00:00:00Z')"
        )
    db.close()


def test_role_check_constraint(tmp_path):
    db = Database(tmp_path / "anchor.db")
    db.migrate()
    with pytest.raises(sqlite3.IntegrityError):
        db.execute(
            "INSERT INTO users(role, display_name, auth_subject, created_at) "
            "VALUES ('admin', 'x', 'x', '2026-01-01T00:00:00Z')"
        )
    db.close()


def test_transaction_rolls_back_on_error(tmp_path):
    db = Database(tmp_path / "anchor.db")
    db.migrate()
    with pytest.raises(RuntimeError):
        with db.tx() as conn:
            conn.execute(
                "INSERT INTO users(role, display_name, auth_subject, created_at) "
                "VALUES ('senior', 'a', 'subject-a', '2026-01-01T00:00:00Z')"
            )
            raise RuntimeError("boom")
    assert db.query_one("SELECT COUNT(*) AS n FROM users")["n"] == 0
    db.close()


def test_transaction_commits(tmp_path):
    db = Database(tmp_path / "anchor.db")
    db.migrate()
    with db.tx() as conn:
        conn.execute(
            "INSERT INTO users(role, display_name, auth_subject, created_at) "
            "VALUES ('senior', 'a', 'subject-a', '2026-01-01T00:00:00Z')"
        )
    assert db.query_one("SELECT COUNT(*) AS n FROM users")["n"] == 1
    db.close()


def test_unique_auth_subject(tmp_path):
    db = Database(tmp_path / "anchor.db")
    db.migrate()
    db.execute(
        "INSERT INTO users(role, display_name, auth_subject, created_at) "
        "VALUES ('senior', 'a', 'same', '2026-01-01T00:00:00Z')"
    )
    with pytest.raises(sqlite3.IntegrityError):
        db.execute(
            "INSERT INTO users(role, display_name, auth_subject, created_at) "
            "VALUES ('caregiver', 'b', 'same', '2026-01-01T00:00:00Z')"
        )
    db.close()


def test_activity_rotation_primary_key(tmp_path):
    db = Database(tmp_path / "anchor.db")
    db.migrate()
    db.execute(
        "INSERT INTO users(role, display_name, auth_subject, created_at) "
        "VALUES ('senior', 'a', 's1', '2026-01-01T00:00:00Z')"
    )
    db.execute(
        "INSERT INTO activity_rotation(senior_id, activity_type, last_index, updated_at) "
        "VALUES (1, 'trivia', 0, '2026-01-01T00:00:00Z')"
    )
    with pytest.raises(sqlite3.IntegrityError):
        db.execute(
            "INSERT INTO activity_rotation(senior_id, activity_type, last_index, updated_at) "
            "VALUES (1, 'trivia', 1, '2026-01-01T00:00:00Z')"
        )
    db.close()
