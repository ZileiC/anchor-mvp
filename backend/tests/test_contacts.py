"""Contact/call surface tests (S11) and the generic notification inbox (SPEC §6.6).

A call action resolves an authorised saved contact, records that the user started
the call, and returns a ``tel:`` URI. The backend never dials and never claims the
call connected; ``confirmed`` records the user's own confirmation separately.
"""

from __future__ import annotations

import pytest

from tests.helpers import (
    headers,
    insert_contact,
    insert_notification,
    seed_adequate_observations,
    seed_consents,
)


# -- senior calls ---------------------------------------------------------
def test_s11_senior_contact_action_returns_dial_uri(client, app, senior, senior_token):
    contact_id = insert_contact(app, senior, label="小梅", phone="+86 139-0000-1111")
    response = client.post(
        "/api/v1/contact-actions",
        json={"contact_id": contact_id},
        headers=headers(senior_token),
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["label"] == "小梅"
    assert body["phone"] == "+86 139-0000-1111"
    assert body["dial_uri"] == "tel:+8613900001111"
    assert body["confirmed_at"] is None

    action = app.state.ctx.db.query_one("SELECT * FROM contact_actions WHERE id = ?", (body["contact_action_id"],))
    assert action["actor_user_id"] == senior["id"]
    assert action["senior_id"] == senior["id"]
    assert action["contact_id"] == contact_id
    audit = app.state.ctx.db.query(
        "SELECT * FROM audit_events WHERE action = 'contact_initiated'"
    )
    assert len(audit) == 1
    assert audit[0]["target_type"] == "contact_action"
    assert audit[0]["target_id"] == str(body["contact_action_id"])
    # Audit rows never carry the label or the number.
    assert "139" not in (audit[0]["target_id"] or "")


def test_s11_confirmation_is_recorded_separately(client, app, senior, senior_token):
    contact_id = insert_contact(app, senior)
    confirmed = client.post(
        "/api/v1/contact-actions",
        json={"contact_id": contact_id, "confirmed": True},
        headers=headers(senior_token),
    ).json()
    assert confirmed["confirmed_at"] is not None

    unconfirmed = client.post(
        "/api/v1/contact-actions",
        json={"contact_id": contact_id, "confirmed": False},
        headers=headers(senior_token),
    ).json()
    assert unconfirmed["confirmed_at"] is None
    rows = app.state.ctx.db.query("SELECT * FROM contact_actions ORDER BY id")
    assert len(rows) == 2


def test_s11_unknown_contact_is_404(client, senior_token):
    response = client.post(
        "/api/v1/contact-actions", json={"contact_id": 999}, headers=headers(senior_token)
    )
    assert response.status_code == 404
    assert response.json()["error"]["code"] == "not_found"


def test_s11_other_seniors_contact_is_404(client, app, make_user, senior_token):
    other = make_user("senior", display_name="别人")
    contact_id = insert_contact(app, other)
    response = client.post(
        "/api/v1/contact-actions", json={"contact_id": contact_id}, headers=headers(senior_token)
    )
    assert response.status_code == 404


# -- caregiver calls ------------------------------------------------------
def test_s11_caregiver_can_call_linked_senior_contact(
    client, app, senior, caregiver, linked, caregiver_token
):
    contact_id = insert_contact(app, senior, label="王大妈", phone="13800002222")
    response = client.post(
        "/api/v1/contact-actions",
        json={"contact_id": contact_id},
        headers=headers(caregiver_token),
    )
    assert response.status_code == 200, response.text
    action = app.state.ctx.db.query_one(
        "SELECT * FROM contact_actions WHERE id = ?", (response.json()["contact_action_id"],)
    )
    assert action["actor_user_id"] == caregiver["id"]
    assert action["senior_id"] == senior["id"]


def test_s11_caregiver_cannot_call_another_households_contact(
    client, app, make_user, senior, caregiver, linked, caregiver_token
):
    other_senior = make_user("senior", display_name="别人")
    foreign_contact = insert_contact(app, other_senior)
    response = client.post(
        "/api/v1/contact-actions",
        json={"contact_id": foreign_contact},
        headers=headers(caregiver_token),
    )
    assert response.status_code == 403
    assert response.json()["error"]["code"] == "caregiver_scope_denied"
    assert app.state.ctx.db.query("SELECT * FROM contact_actions") == []


def test_s11_caregiver_without_link_is_denied(client, app, senior, caregiver_token):
    contact_id = insert_contact(app, senior)
    response = client.post(
        "/api/v1/contact-actions", json={"contact_id": contact_id}, headers=headers(caregiver_token)
    )
    assert response.status_code == 403
    assert response.json()["error"]["code"] == "relationship_inactive"


def test_s11_contact_list_never_crosses_households(
    client, app, make_user, senior, caregiver, linked, senior_token, caregiver_token
):
    own_contact = insert_contact(app, senior, label="小梅")
    other_senior = make_user("senior", display_name="别人")
    insert_contact(app, other_senior, label="别人的家属")

    senior_view = client.get("/api/v1/contacts", headers=headers(senior_token)).json()
    assert [item["id"] for item in senior_view["items"]] == [own_contact]

    caregiver_view = client.get("/api/v1/contacts", headers=headers(caregiver_token)).json()
    assert [item["label"] for item in caregiver_view["items"]] == ["小梅"]


def test_s11_contact_endpoints_are_role_neutral_by_contract(
    client, app, senior, caregiver, linked, senior_token, caregiver_token
):
    """Both roles may call; authorization is by ownership/link, not by role."""
    insert_contact(app, senior)
    for token in (senior_token, caregiver_token):
        assert client.get("/api/v1/contacts", headers=headers(token)).status_code == 200


def test_s11_contact_action_requires_a_token(client):
    response = client.post("/api/v1/contact-actions", json={"contact_id": 1})
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "unauthorized"
    assert client.get("/api/v1/contacts").status_code == 401


# -- notifications --------------------------------------------------------
def test_notifications_are_own_and_can_be_marked_read(
    client, app, senior, caregiver, senior_token, caregiver_token
):
    mine = insert_notification(app, senior, title="本周家庭简报已就绪")
    insert_notification(app, caregiver, title="别人的提醒")

    listing = client.get("/api/v1/notifications", headers=headers(senior_token)).json()
    assert [item["id"] for item in listing["items"]] == [mine]
    assert listing["items"][0]["read_at"] is None

    marked = client.patch(f"/api/v1/notifications/{mine}", headers=headers(senior_token))
    assert marked.status_code == 200
    assert marked.json()["read_at"] is not None
    first_read = marked.json()["read_at"]

    again = client.patch(f"/api/v1/notifications/{mine}", headers=headers(senior_token))
    assert again.status_code == 200
    assert again.json()["read_at"] == first_read

    # Another user's row is invisible and not modifiable.
    other = client.patch(f"/api/v1/notifications/{mine}", headers=headers(caregiver_token))
    assert other.status_code == 404
    assert client.get("/api/v1/notifications", headers=headers(caregiver_token)).json()[
        "items"
    ]


@pytest.mark.parametrize("method,path", [("GET", "/api/v1/notifications"), ("PATCH", "/api/v1/notifications/1")])
def test_notifications_require_a_token(client, method, path):
    response = client.request(method, path)
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "unauthorized"


def test_notifications_never_contain_digest_items(client, app, senior, caregiver, linked):
    from app.jobs import JobRunner

    seed_consents(app, senior, record_observations=True, share_topics=("mood",))
    seed_adequate_observations(app, senior, topic="mood", evidence="今天聊到了心情，很好。")
    digest = app.state.ctx.digests.ensure_weekly_digest(
        int(senior["id"]), "2025-12-29", "2026-01-05"
    )
    app.state.ctx.digests.patch(digest["id"], int(senior["id"]), digest["items"])
    app.state.ctx.digests.approve(digest["id"], int(senior["id"]))
    JobRunner(app.state.ctx).run_once()

    rows = app.state.ctx.db.query("SELECT * FROM notifications WHERE user_id = ?", (caregiver["id"],))
    assert rows
    for row in rows:
        assert "心情" not in row["body"]
        assert "心情" not in row["title"]
        assert "digest" not in row["body"]
