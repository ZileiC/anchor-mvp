"""Digest lifecycle: draft -> awaiting_senior_approval -> approved -> delivered.

Implements SPEC §6.6 and §7:

* generation is deterministic and gated by the adequate-data rule;
* an edit invalidates approval and drops any queued delivery;
* approval snapshots the current consent version and enqueues exactly one
  ``notify_digest`` job;
* every caregiver read re-filters items by the current relationship and
  ``share_topic`` consent — raw observations are never returned;
* delivery re-checks the digest state, the relationship and the consents before
  sending a generic notification and marking the digest delivered.
"""

from __future__ import annotations

import json
import sqlite3
from typing import Any, Iterable, Optional

from .. import audit
from ..clock import Clock, iso_utc
from ..consent import SHARE_TOPICS, ConsentService
from ..db import Database
from ..errors import AppError, validation_error
from ..providers.notifier import DatabaseNotifier
from ..relationships import RelationshipService
from . import baseline, language_guard, render

MAX_ITEMS = 3
MAX_TEXT_LENGTH = 300
EDITABLE_STATUSES = ("draft", "awaiting_senior_approval", "approved", "insufficient_data")


def _items(row: dict[str, Any]) -> list[dict[str, Any]]:
    try:
        parsed = json.loads(row["items_json"] or "[]")
    except (TypeError, ValueError):
        return []
    if not isinstance(parsed, list):
        return []
    return [item for item in parsed if isinstance(item, dict)]


def digest_public(
    row: dict[str, Any],
    locale: str = "zh-CN",
    filtered_items: Optional[list[dict[str, Any]]] = None,
) -> dict[str, Any]:
    items = _items(row) if filtered_items is None else filtered_items
    payload: dict[str, Any] = {
        "id": int(row["id"]),
        "period_start": row["period_start"],
        "period_end": row["period_end"],
        "status": row["status"],
        "items": items,
        "consent_version": int(row["consent_version"]),
        "notification_sent_at": row["notification_sent_at"],
        "delivered_at": row["delivered_at"],
        "edited_at": row["edited_at"],
        "created_at": row["created_at"],
        "updated_at": row["updated_at"],
    }
    if row["status"] == "insufficient_data":
        payload["message"] = render.insufficient_message(locale)
    return payload


class DigestService:
    def __init__(
        self,
        db: Database,
        clock: Clock,
        consent: Optional[ConsentService] = None,
        relationships: Optional[RelationshipService] = None,
        notifier: Optional[DatabaseNotifier] = None,
    ) -> None:
        self.db = db
        self.clock = clock
        self.consent = consent or ConsentService(db, clock)
        self.relationships = relationships or RelationshipService(db, clock)
        self.notifier = notifier or DatabaseNotifier(db, clock)

    # -- helpers ---------------------------------------------------------
    def _locale(self, senior_id: int) -> str:
        row = self.db.query_one("SELECT locale FROM users WHERE id = ?", (senior_id,))
        return render.normalise_locale(row["locale"] if row else None)

    def _row(self, digest_id: int) -> Optional[dict[str, Any]]:
        return self.db.query_one("SELECT * FROM digests WHERE id = ?", (digest_id,))

    def get_owned(self, digest_id: int, senior_id: int) -> dict[str, Any]:
        row = self.db.query_one(
            "SELECT * FROM digests WHERE id = ? AND senior_id = ?", (digest_id, senior_id)
        )
        if row is None:
            raise AppError("not_found", "Not found.")
        return row

    def _filter_items(self, row: dict[str, Any]) -> list[dict[str, Any]]:
        allowed = set(self.consent.allowed_topics(int(row["senior_id"])))
        return [
            item
            for item in _items(row)
            if item.get("topic") in allowed and isinstance(item.get("evidence_ids"), list)
            and item["evidence_ids"]
        ]

    # -- generation ------------------------------------------------------
    def _build(self, senior_id: int, period_start: str, period_end: str) -> tuple[str, list]:
        if not self.consent.is_allowed(senior_id, "record_observations"):
            return "insufficient_data", []
        topics = self.consent.allowed_topics(senior_id)
        if not topics:
            return "insufficient_data", []
        if not baseline.adequate_data(self.db, senior_id, period_start, period_end, topics):
            return "insufficient_data", []
        candidates = baseline.select_candidates(
            self.db, senior_id, period_start, period_end, topics
        )
        if not candidates:
            return "insufficient_data", []
        items = render.render_items(candidates, self._locale(senior_id), limit=MAX_ITEMS)
        if not items:
            return "insufficient_data", []
        return "draft", items

    def ensure_weekly_digest(
        self, senior_id: int, period_start: str, period_end: str
    ) -> dict[str, Any]:
        """Create this period's digest once; repeated calls return the same row."""
        existing = self.db.query_one(
            "SELECT * FROM digests WHERE senior_id = ? AND period_start = ?",
            (int(senior_id), period_start),
        )
        if existing is not None:
            return digest_public(existing, self._locale(int(senior_id)))

        status, items = self._build(int(senior_id), period_start, period_end)
        now = iso_utc(self.clock.now())
        consent_version = self.consent.version(int(senior_id))
        try:
            digest_id = self.db.insert(
                "INSERT INTO digests(senior_id, period_start, period_end, status, items_json, "
                "consent_version, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?)",
                (
                    int(senior_id),
                    period_start,
                    period_end,
                    status,
                    json.dumps(items, ensure_ascii=False),
                    consent_version,
                    now,
                    now,
                ),
            )
        except sqlite3.IntegrityError:
            # A concurrent worker created the same (senior, period) row first.
            row = self.db.query_one(
                "SELECT * FROM digests WHERE senior_id = ? AND period_start = ?",
                (int(senior_id), period_start),
            )
            return digest_public(row, self._locale(int(senior_id)))

        audit.write(
            self.db, self.clock, None, "digest_generated", "digest", digest_id, outcome=status
        )
        return digest_public(self._row(digest_id), self._locale(int(senior_id)))

    # -- reads -----------------------------------------------------------
    def list_for_senior(self, senior_id: int) -> dict[str, Any]:
        locale = self._locale(int(senior_id))
        rows = self.db.query(
            "SELECT * FROM digests WHERE senior_id = ? ORDER BY period_start DESC, id DESC",
            (int(senior_id),),
        )
        return {"items": [digest_public(row, locale) for row in rows]}

    def list_for_caregiver(self, caregiver_id: int) -> dict[str, Any]:
        link = self.relationships.linked_senior(int(caregiver_id))
        if link is None:
            return {"items": [], "note": "insufficient_information"}
        senior_id = int(link["senior_id"])
        locale = self._locale(senior_id)
        rows = self.db.query(
            "SELECT * FROM digests WHERE senior_id = ? AND status IN ('approved','delivered') "
            "ORDER BY period_start DESC, id DESC",
            (senior_id,),
        )
        items = [
            digest_public(row, locale, filtered_items=self._filter_items(row)) for row in rows
        ]
        payload: dict[str, Any] = {"items": items}
        if not items or all(not digest["items"] for digest in items):
            payload["note"] = "insufficient_information"
        return payload

    def view_for(self, user: dict[str, Any], digest_id: int) -> dict[str, Any]:
        if user["role"] == "senior":
            row = self.get_owned(digest_id, int(user["id"]))
            return digest_public(row, self._locale(int(row["senior_id"])))
        link = self.relationships.linked_senior(int(user["id"]))
        row = self._row(int(digest_id))
        if (
            link is None
            or row is None
            or int(row["senior_id"]) != int(link["senior_id"])
            or row["status"] not in ("approved", "delivered")
        ):
            raise AppError("caregiver_scope_denied", "This weekly update is not shared with you.")
        return digest_public(
            row, self._locale(int(row["senior_id"])), filtered_items=self._filter_items(row)
        )

    # -- edit / approve ---------------------------------------------------
    def _validate_item(self, senior_id: int, item: Any) -> dict[str, Any]:
        if not isinstance(item, dict):
            raise validation_error("Each digest item must be an object.")
        topic = item.get("topic")
        if topic not in SHARE_TOPICS:
            raise validation_error(
                "Each digest item needs a known topic.", allowed_topics=list(SHARE_TOPICS)
            )
        text = item.get("text")
        if not isinstance(text, str) or not text.strip():
            raise validation_error("Each digest item needs text.")
        cleaned = text.strip()
        if len(cleaned) > MAX_TEXT_LENGTH:
            raise validation_error(f"Digest item text must be at most {MAX_TEXT_LENGTH} characters.")
        if not language_guard.is_clean(cleaned):
            raise validation_error(
                "Digest text may not contain diagnoses, scores or risk language."
            )
        raw_ids = item.get("evidence_ids")
        if not isinstance(raw_ids, list) or not raw_ids:
            raise validation_error("Each digest item needs at least one evidence reference.")
        evidence_ids: list[int] = []
        for raw in raw_ids:
            if not isinstance(raw, int) or isinstance(raw, bool):
                raise validation_error("evidence_ids must be observation ids (integers).")
            if raw in evidence_ids:
                continue
            observation = self.db.query_one(
                "SELECT id, topic FROM observations WHERE id = ? AND senior_id = ?",
                (raw, int(senior_id)),
            )
            if observation is None or observation["topic"] != topic:
                raise validation_error("Evidence does not support this digest item.")
            evidence_ids.append(raw)
        return {"topic": topic, "text": cleaned, "evidence_ids": evidence_ids}

    def patch(self, digest_id: int, senior_id: int, items: Iterable[Any]) -> dict[str, Any]:
        row = self.get_owned(digest_id, int(senior_id))
        if row["status"] not in EDITABLE_STATUSES:
            raise AppError("conflict", "This weekly update can no longer be edited.")
        if not isinstance(items, list) or not items:
            raise validation_error("A weekly update needs at least one item.")
        if len(items) > MAX_ITEMS:
            raise validation_error(f"A weekly update shows at most {MAX_ITEMS} items.")
        cleaned = [self._validate_item(int(senior_id), item) for item in items]

        now = iso_utc(self.clock.now())
        with self.db.tx() as conn:
            conn.execute(
                "UPDATE digests SET status = 'awaiting_senior_approval', items_json = ?, "
                "edited_by = ?, edited_at = ?, notification_sent_at = NULL, delivered_at = NULL, "
                "updated_at = ? WHERE id = ?",
                (
                    json.dumps(cleaned, ensure_ascii=False),
                    str(senior_id),
                    now,
                    now,
                    digest_id,
                ),
            )
            conn.execute(
                "DELETE FROM jobs WHERE job_type = 'notify_digest' AND idempotency_key = ? "
                "AND status IN ('pending','failed')",
                (f"notify_digest:{digest_id}",),
            )
        audit.write(self.db, self.clock, senior_id, "digest_edited", "digest", digest_id)
        return digest_public(
            self._row(digest_id), self._locale(int(senior_id))
        )

    def approve(self, digest_id: int, senior_id: int) -> dict[str, Any]:
        row = self.get_owned(digest_id, int(senior_id))
        if row["status"] != "awaiting_senior_approval":
            raise AppError("conflict", "Only a draft awaiting approval can be approved.")
        now = iso_utc(self.clock.now())
        version = self.consent.version(int(senior_id))
        with self.db.tx() as conn:
            conn.execute(
                "UPDATE digests SET status = 'approved', consent_version = ?, updated_at = ? "
                "WHERE id = ?",
                (version, now, digest_id),
            )
            conn.execute(
                "INSERT OR IGNORE INTO jobs(job_type, payload_json, due_at, status, "
                "idempotency_key, created_at, updated_at) VALUES ('notify_digest', ?, ?, "
                "'pending', ?, ?, ?)",
                (
                    json.dumps(
                        {"digest_id": int(digest_id), "senior_id": int(senior_id)},
                        ensure_ascii=False,
                    ),
                    now,
                    f"notify_digest:{digest_id}",
                    now,
                    now,
                ),
            )
        audit.write(self.db, self.clock, senior_id, "digest_approved", "digest", digest_id)
        return digest_public(self._row(digest_id), self._locale(int(senior_id)))

    # -- delivery (worker) ------------------------------------------------
    def _cancel(self, digest_id: int) -> None:
        now = iso_utc(self.clock.now())
        with self.db.tx() as conn:
            conn.execute(
                "UPDATE digests SET status = 'cancelled', updated_at = ? WHERE id = ?",
                (now, digest_id),
            )
            conn.execute(
                "DELETE FROM jobs WHERE job_type = 'notify_digest' AND idempotency_key = ? "
                "AND status IN ('pending','failed')",
                (f"notify_digest:{digest_id}",),
            )
        audit.write(self.db, self.clock, None, "digest_cancelled", "digest", digest_id)

    def deliver(self, digest_id: int) -> dict[str, Any]:
        """Deliver an approved digest if — and only if — it is still permitted."""
        digest = self._row(int(digest_id))
        if digest is None:
            return {"delivered": False, "reason": "missing"}
        if digest["status"] != "approved":
            return {"delivered": False, "reason": "not_approved"}

        senior_id = int(digest["senior_id"])
        links = self.db.query(
            "SELECT * FROM relationships WHERE senior_id = ? AND status = 'accepted' "
            "ORDER BY id",
            (senior_id,),
        )
        if not links:
            self._cancel(int(digest_id))
            return {"delivered": False, "reason": "relationship_inactive"}

        allowed = set(self.consent.allowed_topics(senior_id))
        permitted = [
            item
            for item in _items(digest)
            if item.get("topic") in allowed and item.get("evidence_ids")
        ]
        if not permitted:
            self._cancel(int(digest_id))
            return {"delivered": False, "reason": "no_permitted_topics"}

        now = iso_utc(self.clock.now())
        notification_ids: list[int] = []
        with self.db.tx() as conn:
            cursor = conn.execute(
                "UPDATE digests SET status = 'delivered', notification_sent_at = ?, "
                "delivered_at = ?, updated_at = ? WHERE id = ? AND status = 'approved'",
                (now, now, now, int(digest_id)),
            )
            if cursor.rowcount == 0:
                return {"delivered": False, "reason": "not_approved"}
            for link in links:
                notification_ids.append(
                    self.notifier.notify(int(link["caregiver_id"]), "digest_ready", "digest_ready")
                )
        audit.write(self.db, self.clock, None, "digest_delivered", "digest", digest_id)
        return {
            "delivered": True,
            "notification_ids": notification_ids,
            "caregiver_ids": [int(link["caregiver_id"]) for link in links],
        }


__all__ = ["DigestService", "digest_public"]
