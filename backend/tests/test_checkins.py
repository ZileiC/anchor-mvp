"""Proactive check-ins (SPEC §6.2, S1/S7 + quiet-hours failure test)."""

from __future__ import annotations

from datetime import datetime, timezone

from tests.helpers import headers, seed_consents

DEVICE = "tablet-kitchen"


def _prepare(app, senior, *, consents: bool = True, **prefs):
    if consents:
        seed_consents(app, senior, proactive_invitations=True)
    base = {"designated_device_id": DEVICE}
    base.update(prefs)
    app.state.ctx.preferences.patch(int(senior["id"]), base)


def _eligibility(client, token, device: str | None = DEVICE):
    params = {} if device is None else {"device_id": device}
    response = client.get("/api/v1/checkins/eligibility", params=params, headers=headers(token))
    assert response.status_code == 200, response.text
    return response.json()


def _attempt(client, token, outcome="shown", device: str | None = DEVICE):
    return client.post(
        "/api/v1/checkins/attempts",
        json={"device_id": device, "outcome": outcome},
        headers=headers(token),
    )


def test_s1_eligible_inside_greeting_window(client, app, senior, senior_token):
    _prepare(app, senior)
    body = _eligibility(client, senior_token)
    assert body["eligible"] is True
    assert body["reasons"] == []
    assert body["cap_remaining"] == 1
    assert body["local_time"] == "09:00"
    assert body["local_date"] == "2026-01-05"
    assert body["designated_device_ok"] is True
    assert body["window"] == {"start": "09:00", "end": "11:00"}
    assert body["quiet_hours"] == {"start": "21:00", "end": "08:00"}


def test_s1_consent_off_blocks_attempt(client, app, senior, senior_token):
    _prepare(app, senior, consents=False)
    body = _eligibility(client, senior_token)
    assert body["eligible"] is False
    assert "consent_off" in body["reasons"]
    response = _attempt(client, senior_token)
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "consent_required"
    assert app.state.ctx.db.query("SELECT * FROM checkin_events") == []


def test_s1_no_designated_device(client, app, senior, senior_token):
    _prepare(app, senior, designated_device_id=None)
    body = _eligibility(client, senior_token)
    assert "no_designated_device" in body["reasons"]
    assert body["designated_device_ok"] is False
    response = _attempt(client, senior_token)
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "not_designated_device"


def test_s1_wrong_device_is_rejected(client, app, senior, senior_token):
    _prepare(app, senior)
    body = _eligibility(client, senior_token, device="phone-living-room")
    assert "designated_device_mismatch" in body["reasons"]
    response = _attempt(client, senior_token, device="phone-living-room")
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "not_designated_device"


def test_s1_attempt_records_and_cap_blocks_second(client, app, senior, senior_token):
    _prepare(app, senior)
    first = _attempt(client, senior_token, outcome="shown")
    assert first.status_code == 200, first.text
    assert first.json()["cap_remaining"] == 0

    second = _attempt(client, senior_token, outcome="shown")
    assert second.status_code == 409
    assert second.json()["error"]["code"] == "daily_cap_reached"

    body = _eligibility(client, senior_token)
    assert body["eligible"] is False
    assert "daily_cap_reached" in body["reasons"]
    assert body["cap_remaining"] == 0
    rows = app.state.ctx.db.query("SELECT * FROM checkin_events")
    assert len(rows) == 1
    assert rows[0]["local_date"] == "2026-01-05"


def test_s1_dismissed_is_not_retried_same_day(client, app, senior, senior_token):
    _prepare(app, senior)
    assert _attempt(client, senior_token, outcome="dismissed").status_code == 200
    retry = _attempt(client, senior_token, outcome="shown")
    assert retry.status_code == 409
    assert retry.json()["error"]["code"] == "daily_cap_reached"
    schedule = client.get("/api/v1/checkins/schedule", headers=headers(senior_token)).json()
    assert schedule["entries"][0]["date"] == "2026-01-06"


def test_s1_outside_window(client, app, senior, senior_token, clock):
    _prepare(app, senior)
    clock.advance(hours=6)  # 07:00Z -> 15:00 Asia/Shanghai
    body = _eligibility(client, senior_token)
    assert "outside_greeting_window" in body["reasons"]
    response = _attempt(client, senior_token)
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "outside_greeting_window"


def test_s1_quiet_hours_block_attempt(client, app, senior, senior_token, clock):
    _prepare(app, senior, greeting_start="21:00", greeting_end="23:30")
    clock.advance(hours=13)  # 14:00Z -> 22:00 Asia/Shanghai
    body = _eligibility(client, senior_token)
    assert "quiet_hours" in body["reasons"]
    response = _attempt(client, senior_token)
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "quiet_hours"


def test_s1_paused_and_snoozed_block(client, app, senior, senior_token):
    _prepare(app, senior, paused=True)
    assert _attempt(client, senior_token).json()["error"]["code"] == "conflict"
    assert client.get("/api/v1/checkins/schedule", headers=headers(senior_token)).json() == {
        "entries": [],
        "note": "paused",
    }

    app.state.ctx.preferences.patch(int(senior["id"]), {"paused": False, "snoozed_until": "2026-01-06T01:00:00Z"})
    body = _eligibility(client, senior_token)
    assert "snoozed" in body["reasons"]
    assert _attempt(client, senior_token).json()["error"]["code"] == "conflict"
    assert client.get("/api/v1/checkins/schedule", headers=headers(senior_token)).json() == {
        "entries": [],
        "note": "snoozed",
    }


def test_s1_daily_cap_zero_empties_schedule(client, app, senior, senior_token):
    _prepare(app, senior, daily_cap=0)
    body = _eligibility(client, senior_token)
    assert "daily_cap_reached" in body["reasons"]
    schedule = client.get("/api/v1/checkins/schedule", headers=headers(senior_token)).json()
    assert schedule == {"entries": [], "note": "daily_cap_zero"}


def test_s1_schedule_lists_seven_days(client, app, senior, senior_token):
    _prepare(app, senior)
    schedule = client.get("/api/v1/checkins/schedule", headers=headers(senior_token)).json()
    assert schedule["note"] in ("", "no_designated_device")
    entries = schedule["entries"]
    assert len(entries) == 7
    assert [entry["date"] for entry in entries] == [
        "2026-01-05",
        "2026-01-06",
        "2026-01-07",
        "2026-01-08",
        "2026-01-09",
        "2026-01-10",
        "2026-01-11",
    ]
    assert all(entry["local_time"] == "09:00" for entry in entries)
    assert all(entry["title"] and entry["body"] for entry in entries)


def test_s1_schedule_is_localised(client, app, senior, senior_token):
    app.state.ctx.db.execute("UPDATE users SET locale = 'en' WHERE id = ?", (senior["id"],))
    _prepare(app, senior)
    schedule = client.get("/api/v1/checkins/schedule", headers=headers(senior_token)).json()
    assert schedule["entries"][0]["title"] == "Good morning"


def test_s1_active_session_blocks(client, app, senior, senior_token):
    from app.clock import iso_utc

    _prepare(app, senior)
    ctx = app.state.ctx
    session_id = "11111111-1111-1111-1111-111111111111"
    ctx.db.execute(
        "INSERT INTO sessions(id, senior_id, origin, state, cancellation_token, started_at) "
        "VALUES (?,?,?,?,?,?)",
        (session_id, int(senior["id"]), "voluntary", "active", "tok", iso_utc(ctx.clock.now())),
    )
    body = _eligibility(client, senior_token)
    assert "active_session" in body["reasons"]
    response = _attempt(client, senior_token)
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "conflict"
    assert response.json()["error"]["session_id"] == session_id


def test_s1_invalid_outcome(client, app, senior, senior_token):
    _prepare(app, senior)
    response = _attempt(client, senior_token, outcome="ignored")
    assert response.status_code == 422


def test_failure_quiet_hours_midnight(client, app, senior, senior_token, clock):
    """Quiet hours cross midnight, and a timezone change never adds invitations."""
    _prepare(
        app,
        senior,
        quiet_start="22:00",
        quiet_end="08:00",
        greeting_start="07:00",
        greeting_end="23:59",
    )

    clock.set(datetime(2026, 1, 5, 15, 0, tzinfo=timezone.utc))
    # 15:00Z == 23:00 Asia/Shanghai: inside the midnight-crossing quiet window.
    body = _eligibility(client, senior_token)
    assert body["eligible"] is False
    assert "quiet_hours" in body["reasons"]
    assert _attempt(client, senior_token).json()["error"]["code"] == "quiet_hours"

    clock.set(datetime(2026, 1, 5, 22, 30, tzinfo=timezone.utc))  # 06:30 +08:00 -> still quiet
    assert "quiet_hours" in _eligibility(client, senior_token)["reasons"]
    assert _attempt(client, senior_token).json()["error"]["code"] == "quiet_hours"

    clock.set(datetime(2026, 1, 5, 4, 0, tzinfo=timezone.utc))  # 12:00 +08:00 -> allowed
    assert _eligibility(client, senior_token)["eligible"] is True

    # Move the senior to New York: 04:00Z is 23:00 the previous evening -> quiet hours.
    app.state.ctx.db.execute(
        "UPDATE users SET timezone = 'America/New_York' WHERE id = ?", (senior["id"],)
    )
    ny = _eligibility(client, senior_token)
    assert ny["eligible"] is False
    assert "quiet_hours" in ny["reasons"]
    assert ny["local_date"] == "2026-01-04"
    assert _attempt(client, senior_token).status_code == 409
    assert app.state.ctx.db.query("SELECT * FROM checkin_events") == []

    # A timezone change must not create invitations either.
    schedule = client.get("/api/v1/checkins/schedule", headers=headers(senior_token)).json()
    assert schedule["entries"][0]["date"] == "2026-01-04"
