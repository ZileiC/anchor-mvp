"""Digest surface tests (S10) and the required digest failure tests.

Covers generation rules (SPEC §7), the draft/edit/approve lifecycle, caregiver
filtering by current consent and the two required failure scenarios
``failure_revoke_after_draft`` / ``failure_sparse_data``.
"""

from __future__ import annotations

import json
from datetime import date, timedelta

import pytest

from app.digests import language_guard, render
from app.jobs import JobRunner
from tests.helpers import (
    DIGEST_PERIOD_END,
    DIGEST_PERIOD_START,
    headers,
    insert_digest,
    insert_observation,
    link_relationship,
    seed_adequate_observations,
    seed_consents,
    token_for,
)

PERIOD = (DIGEST_PERIOD_START, DIGEST_PERIOD_END)
ALL_TOPICS = ("participation", "activities", "mood", "meals", "wellbeing")


def _generate(app, senior):
    return app.state.ctx.digests.ensure_weekly_digest(int(senior["id"]), *PERIOD)


def _confirm(client, digest, senior_token, items=None):
    response = client.patch(
        f"/api/v1/digests/{digest['id']}",
        json={"items": items if items is not None else digest["items"]},
        headers=headers(senior_token),
    )
    assert response.status_code == 200, response.text
    return response.json()


def _approved_digest(client, app, senior, senior_token, items=None):
    digest = _generate(app, senior)
    assert digest["status"] == "draft", digest
    awaiting = _confirm(client, digest, senior_token, items)
    assert awaiting["status"] == "awaiting_senior_approval"
    response = client.post(
        f"/api/v1/digests/{digest['id']}/approve", headers=headers(senior_token)
    )
    assert response.status_code == 200, response.text
    return response.json()


def _consent_version(client, senior_token):
    body = client.get("/api/v1/consents", headers=headers(senior_token)).json()
    return body["version"]


# -- generation -----------------------------------------------------------
def test_s10_generates_supported_items_ranked_by_change(client, app, senior, senior_token):
    seed_consents(
        app, senior, record_observations=True, share_topics=ALL_TOPICS
    )
    seed_adequate_observations(app, senior, topic="mood", evidence="今天心情不错。")
    seed_adequate_observations(app, senior, topic="meals", current_offsets=(0, 2))
    insert_observation(
        app,
        senior,
        topic="activities",
        event_date=date.fromisoformat(DIGEST_PERIOD_START).isoformat(),
        evidence="下午给花浇了水。",
    )

    digest = _generate(app, senior)
    assert digest["status"] == "draft"
    items = digest["items"]
    assert 1 <= len(items) <= 3
    # activities had no prior evidence -> "appeared" ranks first.
    assert items[0]["topic"] == "activities"
    for item in items:
        assert item["topic"] in ALL_TOPICS
        assert item["text"].strip()
        assert item["evidence_ids"]
        assert all(isinstance(value, int) for value in item["evidence_ids"])
        assert language_guard.is_clean(item["text"])

    stored = app.state.ctx.db.query_one(
        "SELECT * FROM digests WHERE id = ?", (digest["id"],)
    )
    assert stored["status"] == "draft"


def test_s10_insufficient_data_preview_message(client, app, senior, senior_token):
    seed_consents(app, senior, record_observations=True, share_topics=ALL_TOPICS)
    # Only two observed days: below the adequate-data rule.
    insert_observation(app, senior, topic="mood", event_date="2025-12-29")
    insert_observation(app, senior, topic="mood", event_date="2025-12-30")

    digest = _generate(app, senior)
    assert digest["status"] == "insufficient_data"
    assert digest["items"] == []
    assert digest["message"] == "这周的信息还不够，先不下结论。"

    preview = client.get("/api/v1/digests", headers=headers(senior_token)).json()
    assert preview["items"][0]["status"] == "insufficient_data"
    assert preview["items"][0]["message"] == "这周的信息还不够，先不下结论。"


def failure_sparse_data(client, app, senior, senior_token):
    """SPEC §10 required failure test: sparse data is reported honestly."""
    seed_consents(app, senior, record_observations=True, share_topics=("mood",))
    for day in ("2025-12-29", "2025-12-31", "2026-01-02"):
        insert_observation(app, senior, topic="mood", event_date=day)
    # Prior 14 days stay empty (0 < 6), so the week is not describable yet.
    digest = _generate(app, senior)
    assert digest["status"] == "insufficient_data"
    assert digest["items"] == []
    assert "不够" in digest["message"]
    assert len(digest["items"]) < 3  # never padded to three


def test_s10_senior_preview_lists_every_state(client, app, senior, senior_token):
    seed_consents(app, senior, record_observations=True, share_topics=ALL_TOPICS)
    insert_observation(app, senior, topic="mood", event_date="2025-12-29")
    insert_digest(
        app,
        senior,
        status="awaiting_senior_approval",
        period_start="2026-01-05",
        items=[
            {
                "topic": "mood",
                "text": "这周有 2 天聊到了心情。",
                "evidence_ids": [1],
            }
        ],
    )
    _generate(app, senior)
    body = client.get("/api/v1/digests", headers=headers(senior_token)).json()
    statuses = {item["status"] for item in body["items"]}
    assert {"awaiting_senior_approval", "insufficient_data"} <= statuses


def test_s10_english_locale_renders_english(client, app, senior, senior_token):
    app.state.ctx.db.execute("UPDATE users SET locale = 'en' WHERE id = ?", (senior["id"],))
    seed_consents(app, senior, record_observations=True, share_topics=ALL_TOPICS)
    seed_adequate_observations(app, senior, topic="mood", evidence="felt good today")
    digest = _generate(app, senior)
    assert digest["status"] == "draft"
    assert any("You talked about" in item["text"] for item in digest["items"])


# -- lifecycle ------------------------------------------------------------
def test_s10_edit_then_approve_enqueues_one_notify_job(client, app, senior, senior_token):
    seed_consents(app, senior, record_observations=True, share_topics=ALL_TOPICS)
    seed_adequate_observations(app, senior, topic="mood")
    digest = _generate(app, senior)

    edited_item = dict(digest["items"][0])
    edited_item["text"] = "这周聊到了心情，可以问问最近怎么样。"
    awaiting = _confirm(client, digest, senior_token, [edited_item])
    assert awaiting["status"] == "awaiting_senior_approval"
    assert awaiting["edited_at"] is not None

    approved = client.post(
        f"/api/v1/digests/{digest['id']}/approve", headers=headers(senior_token)
    )
    assert approved.status_code == 200, approved.text
    body = approved.json()
    assert body["status"] == "approved"
    assert body["consent_version"] == _consent_version(client, senior_token)

    jobs = app.state.ctx.db.query(
        "SELECT * FROM jobs WHERE idempotency_key = ?", (f"notify_digest:{digest['id']}",)
    )
    assert len(jobs) == 1
    assert jobs[0]["status"] == "pending"

    again = client.post(
        f"/api/v1/digests/{digest['id']}/approve", headers=headers(senior_token)
    )
    assert again.status_code == 409
    assert again.json()["error"]["code"] == "conflict"


def test_s10_edit_after_approval_invalidates_approval(client, app, senior, senior_token):
    seed_consents(app, senior, record_observations=True, share_topics=ALL_TOPICS)
    seed_adequate_observations(app, senior, topic="mood")
    digest = _approved_digest(client, app, senior, senior_token)

    item = dict(digest["items"][0])
    item["text"] = "这周有几天聊到了心情，和以前差不多。"
    response = client.patch(
        f"/api/v1/digests/{digest['id']}",
        json={"items": [item]},
        headers=headers(senior_token),
    )
    assert response.status_code == 200, response.text
    updated = response.json()
    assert updated["status"] == "awaiting_senior_approval"
    assert updated["notification_sent_at"] is None
    jobs = app.state.ctx.db.query(
        "SELECT * FROM jobs WHERE idempotency_key = ?", (f"notify_digest:{digest['id']}",)
    )
    assert jobs == []


def test_s10_patch_rejects_more_than_three_items(client, app, senior, senior_token):
    seed_consents(app, senior, record_observations=True, share_topics=ALL_TOPICS)
    seed_adequate_observations(app, senior, topic="mood")
    digest = _generate(app, senior)
    item = dict(digest["items"][0])
    response = client.patch(
        f"/api/v1/digests/{digest['id']}",
        json={"items": [item, item, item, item]},
        headers=headers(senior_token),
    )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"


def test_s10_patch_rejects_diagnostic_language(client, app, senior, senior_token):
    seed_consents(app, senior, record_observations=True, share_topics=ALL_TOPICS)
    seed_adequate_observations(app, senior, topic="mood")
    digest = _generate(app, senior)
    base = dict(digest["items"][0])
    for banned_text in ("认知评分 62 分", "Possible dementia, risk level high"):
        item = {**base, "text": banned_text}
        response = client.patch(
            f"/api/v1/digests/{digest['id']}",
            json={"items": [item]},
            headers=headers(senior_token),
        )
        assert response.status_code == 422, response.text
        assert response.json()["error"]["code"] == "validation_error"


def test_s10_banned_patterns_cover_the_spec_list():
    expected = [
        "诊断",
        "痴呆",
        "认知",
        "抑郁",
        "评分",
        "分数",
        "健康分",
        "预警",
        "退化",
        "dementia",
        "diagnosis",
        "cognitive",
        "depression",
        "score",
        "risk level",
    ]
    for pattern in expected:
        assert language_guard.find_banned(f"...{pattern}..."), pattern


def test_s10_generation_guard_falls_back_to_safe_template(monkeypatch):
    monkeypatch.setitem(render.TEMPLATES["steady"], "zh-CN", "认知评分 {current_count} 分")
    item = render.render_item(
        {
            "topic": "mood",
            "current_count": 2,
            "baseline_count": 2,
            "delta": 0.0,
            "evidence_ids": [7],
        },
        "zh-CN",
    )
    assert item["text"] == render.SAFE_FALLBACK["zh-CN"]
    assert language_guard.is_clean(item["text"])
    assert item["evidence_ids"] == [7]


def test_s10_patch_rejects_unsupported_evidence(client, app, make_user, senior, senior_token):
    seed_consents(app, senior, record_observations=True, share_topics=ALL_TOPICS)
    seed_adequate_observations(app, senior, topic="mood")
    digest = _generate(app, senior)
    other = make_user("senior", display_name="别人")
    foreign_id = insert_observation(
        app, other, topic="mood", event_date="2025-12-29", evidence="别人的话"
    )
    item = dict(digest["items"][0])
    item["evidence_ids"] = [foreign_id]
    response = client.patch(
        f"/api/v1/digests/{digest['id']}",
        json={"items": [item]},
        headers=headers(senior_token),
    )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"


# -- baseline rules (unit level) -----------------------------------------
def test_s10_baseline_adequate_data_rule(app, senior):
    from app.digests import baseline

    seed_consents(app, senior, record_observations=True, share_topics=ALL_TOPICS)
    start, end = PERIOD
    db = app.state.ctx.db
    # 2 current days + 5 prior days: both sides are too thin.
    for day in ("2025-12-29", "2025-12-30"):
        insert_observation(app, senior, topic="mood", event_date=day)
    for offset in (1, 2, 3, 4, 5):
        insert_observation(
            app,
            senior,
            topic="mood",
            event_date=(date.fromisoformat(start) - timedelta(days=offset)).isoformat(),
        )
    assert baseline.observed_days(db, senior["id"], start, end, ALL_TOPICS) == 2
    assert baseline.adequate_data(db, senior["id"], start, end, ALL_TOPICS) is False

    # Six prior days but still only two observed days this week.
    insert_observation(app, senior, topic="mood", event_date="2025-12-23")
    assert baseline.adequate_data(db, senior["id"], start, end, ALL_TOPICS) is False

    # Third current day completes both sides: 3 current + 6 prior passes.
    insert_observation(app, senior, topic="mood", event_date="2025-12-31")
    assert baseline.observed_days(db, senior["id"], start, end, ALL_TOPICS) == 3
    assert baseline.adequate_data(db, senior["id"], start, end, ALL_TOPICS) is True


def test_s10_baseline_flags_changed_and_appeared_topics(app, senior):
    from app.digests import baseline

    seed_consents(app, senior, record_observations=True, share_topics=ALL_TOPICS)
    start, end = PERIOD
    # mood: 1 current day vs 1 prior day -> delta 1/7 - 1/14 = 0.07/day (not changed)
    insert_observation(app, senior, topic="mood", event_date="2025-12-29")
    insert_observation(app, senior, topic="mood", event_date="2025-12-28")
    # meals: 1 current day with no prior evidence -> "appeared" (changed)
    insert_observation(app, senior, topic="meals", event_date="2025-12-30")
    candidates = baseline.select_candidates(
        app.state.ctx.db, senior["id"], start, end, ALL_TOPICS
    )
    by_topic = {candidate["topic"]: candidate for candidate in candidates}
    assert by_topic["meals"]["changed"] is True
    assert by_topic["meals"]["baseline_count"] == 0
    assert by_topic["mood"]["changed"] is False


# -- caregiver filtering --------------------------------------------------
def test_s10_caregiver_filtered_by_current_consent(
    client, app, senior, caregiver, linked, senior_token, caregiver_token
):
    seed_consents(
        app, senior, record_observations=True, share_topics=ALL_TOPICS
    )
    seed_adequate_observations(app, senior, topic="mood", evidence="心情不错。")
    seed_adequate_observations(
        app, senior, topic="meals", evidence="中午吃了红烧肉。", current_offsets=(0, 2)
    )
    digest = _approved_digest(client, app, senior, senior_token)
    assert any(item["topic"] == "meals" for item in digest["items"])
    assert digest["consent_version"] == _consent_version(client, senior_token)

    version = _consent_version(client, senior_token)
    revoked = client.put(
        "/api/v1/consents",
        json={
            "base_version": version,
            "changes": [{"capability": "share_topic", "topic": "meals", "allowed": False}],
        },
        headers=headers(senior_token),
    )
    assert revoked.status_code == 200, revoked.text
    assert _consent_version(client, senior_token) > digest["consent_version"]

    # The stored digest is untouched; the caregiver view is re-filtered.
    stored = app.state.ctx.db.query_one(
        "SELECT * FROM digests WHERE id = ?", (digest["id"],)
    )
    stored_items = json.loads(stored["items_json"])
    assert any(item["topic"] == "meals" for item in stored_items)

    view = client.get("/api/v1/digests", headers=headers(caregiver_token)).json()
    assert view["items"], view
    visible_items = view["items"][0]["items"]
    assert visible_items
    assert all(item["topic"] != "meals" for item in visible_items)

    detail = client.get(
        f"/api/v1/digests/{digest['id']}", headers=headers(caregiver_token)
    )
    assert detail.status_code == 200
    assert all(item["topic"] != "meals" for item in detail.json()["items"])

    # Never raw observations, only ids.
    blob = json.dumps(detail.json(), ensure_ascii=False)
    assert "红烧肉" not in blob
    assert '"evidence"' not in blob


def test_s10_caregiver_never_sees_unapproved_digest(
    client, app, senior, caregiver, linked, senior_token, caregiver_token
):
    seed_consents(app, senior, record_observations=True, share_topics=ALL_TOPICS)
    seed_adequate_observations(app, senior, topic="mood")
    digest = _generate(app, senior)
    assert digest["status"] == "draft"

    listing = client.get("/api/v1/digests", headers=headers(caregiver_token)).json()
    assert listing["items"] == []
    assert listing["note"] == "insufficient_information"

    detail = client.get(
        f"/api/v1/digests/{digest['id']}", headers=headers(caregiver_token)
    )
    assert detail.status_code == 403
    assert detail.json()["error"]["code"] == "caregiver_scope_denied"


def test_s10_caregiver_sees_delivered_digest(
    client, app, senior, caregiver, linked, senior_token, caregiver_token
):
    seed_consents(app, senior, record_observations=True, share_topics=ALL_TOPICS)
    seed_adequate_observations(app, senior, topic="mood")
    digest = _approved_digest(client, app, senior, senior_token)
    JobRunner(app.state.ctx).run_once()

    body = client.get("/api/v1/digests", headers=headers(caregiver_token)).json()
    assert body["items"][0]["status"] == "delivered"
    assert body["items"][0]["items"]
    assert body["items"][0]["delivered_at"] is not None


# -- required failure tests ----------------------------------------------
def failure_revoke_after_draft(
    client, app, senior, caregiver, linked, senior_token, caregiver_token
):
    """Revoking a topic after approval blocks it at retrieval and at delivery."""
    seed_consents(app, senior, record_observations=True, share_topics=("mood",))
    seed_adequate_observations(app, senior, topic="mood")
    digest = _approved_digest(client, app, senior, senior_token)

    version = _consent_version(client, senior_token)
    revoke = client.put(
        "/api/v1/consents",
        json={
            "base_version": version,
            "changes": [{"capability": "share_topic", "topic": "mood", "allowed": False}],
        },
        headers=headers(senior_token),
    )
    assert revoke.status_code == 200, revoke.text

    # Retrieval: the approved digest now shows zero permitted items.
    before_delivery = client.get(
        f"/api/v1/digests/{digest['id']}", headers=headers(caregiver_token)
    )
    assert before_delivery.status_code == 200
    assert before_delivery.json()["items"] == []

    # Delivery: the notify job re-checks consent, cancels and sends nothing.
    results = JobRunner(app.state.ctx).run_once()
    assert any(item["job_type"] == "notify_digest" for item in results)
    stored = app.state.ctx.db.query_one(
        "SELECT * FROM digests WHERE id = ?", (digest["id"],)
    )
    assert stored["status"] == "cancelled"
    assert stored["delivered_at"] is None
    notifications = app.state.ctx.db.query(
        "SELECT * FROM notifications WHERE user_id = ? AND kind = 'digest_ready'",
        (caregiver["id"],),
    )
    assert notifications == []

    # Retrieval after cancellation is denied.
    detail = client.get(
        f"/api/v1/digests/{digest['id']}", headers=headers(caregiver_token)
    )
    assert detail.status_code == 403
    assert detail.json()["error"]["code"] == "caregiver_scope_denied"
    listing = client.get("/api/v1/digests", headers=headers(caregiver_token)).json()
    assert listing["items"] == []


def failure_cross_household(
    client, app, make_user, senior, caregiver, linked, senior_token, caregiver_token
):
    """A caregiver cannot read another household's digest or change its consent."""
    other_senior = make_user("senior", display_name="另一位老人")
    other_caregiver = make_user("caregiver", display_name="另一位家属")
    link_relationship(app, other_senior, other_caregiver, status="accepted")
    other_token = token_for(app, other_caregiver)
    seed_consents(app, senior, record_observations=True, share_topics=ALL_TOPICS)
    seed_consents(app, other_senior, record_observations=True, share_topics=ALL_TOPICS)
    seed_adequate_observations(app, senior, topic="mood")
    digest = _approved_digest(client, app, senior, senior_token)

    detail = client.get(
        f"/api/v1/digests/{digest['id']}", headers=headers(other_token)
    )
    assert detail.status_code == 403
    assert detail.json()["error"]["code"] == "caregiver_scope_denied"

    listing = client.get("/api/v1/digests", headers=headers(other_token)).json()
    assert all(item["id"] != digest["id"] for item in listing["items"])

    edit = client.patch(
        f"/api/v1/digests/{digest['id']}",
        json={"items": digest["items"]},
        headers=headers(other_token),
    )
    assert edit.status_code == 403
    assert edit.json()["error"]["code"] == "forbidden"

    approve = client.post(
        f"/api/v1/digests/{digest['id']}/approve", headers=headers(other_token)
    )
    assert approve.status_code == 403

    consent = client.put(
        "/api/v1/consents",
        json={"base_version": 1, "changes": []},
        headers=headers(other_token),
    )
    assert consent.status_code == 403
    assert consent.json()["error"]["code"] == "forbidden"

    # The linked caregiver likewise cannot read the other household's digest.
    other_digest = insert_digest(app, other_senior, status="approved")
    blocked = client.get(
        f"/api/v1/digests/{other_digest}", headers=headers(caregiver_token)
    )
    assert blocked.status_code == 403


# -- authorization --------------------------------------------------------
@pytest.mark.parametrize(
    "method,path,body",
    [
        ("GET", "/api/v1/digests", None),
        ("GET", "/api/v1/digests/1", None),
        ("PATCH", "/api/v1/digests/1", {"items": []}),
        ("POST", "/api/v1/digests/1/approve", None),
    ],
)
def test_s10_digest_endpoints_require_a_token(client, method, path, body):
    response = client.request(method, path, json=body)
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "unauthorized"


def test_s10_caregiver_cannot_edit_or_approve(client, app, senior, linked, caregiver_token):
    digest_id = insert_digest(app, senior, status="awaiting_senior_approval")
    edit = client.patch(
        f"/api/v1/digests/{digest_id}", json={"items": []}, headers=headers(caregiver_token)
    )
    assert edit.status_code == 403
    assert edit.json()["error"]["code"] == "forbidden"
    approve = client.post(
        f"/api/v1/digests/{digest_id}/approve", headers=headers(caregiver_token)
    )
    assert approve.status_code == 403


def test_s10_senior_cannot_read_another_seniors_digest(
    client, app, make_user, senior_token
):
    other = make_user("senior", display_name="别人")
    digest_id = insert_digest(app, other, status="approved")
    response = client.get(f"/api/v1/digests/{digest_id}", headers=headers(senior_token))
    assert response.status_code == 404
    assert response.json()["error"]["code"] == "not_found"


# SPEC §10 names the required failure tests exactly ``failure_*``; pytest only
# collects ``test_*`` names, so each exact-named function gets a collectable alias.
test_failure_sparse_data = failure_sparse_data
test_failure_revoke_after_draft = failure_revoke_after_draft
test_failure_cross_household = failure_cross_household
