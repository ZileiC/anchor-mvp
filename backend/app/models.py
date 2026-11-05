"""Row -> dict serializers shared by services and the HTTP layer."""

from __future__ import annotations

import json
from typing import Any, Optional


def user_public(row: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": row["id"],
        "role": row["role"],
        "display_name": row["display_name"],
        "timezone": row["timezone"],
        "locale": row["locale"],
    }


def me_payload(
    row: dict[str, Any],
    senior_id: Optional[int],
    relationship_status: Optional[str],
) -> dict[str, Any]:
    payload = user_public(row)
    payload["senior_id"] = senior_id
    payload["relationship_status"] = relationship_status
    return payload


def preferences_public(row: dict[str, Any]) -> dict[str, Any]:
    """Serialize a ``preferences`` row (JSON columns expanded)."""
    return {
        "senior_id": row["senior_id"],
        "greeting_start": row["greeting_start"],
        "greeting_end": row["greeting_end"],
        "quiet_start": row["quiet_start"],
        "quiet_end": row["quiet_end"],
        "daily_cap": row["daily_cap"],
        "paused": bool(row["paused"]),
        "snoozed_until": row["snoozed_until"],
        "voice_pace": row["voice_pace"],
        "short_replies": bool(row["short_replies"]),
        "language": row["language"],
        "interests": json.loads(row["interests"] or "[]"),
        "observation_topics": json.loads(row["observation_topics"] or "[]"),
        "designated_device_id": row["designated_device_id"],
        "digest_retention_days": row["digest_retention_days"],
        "updated_at": row["updated_at"],
    }


def consent_public(row: dict[str, Any]) -> dict[str, Any]:
    return {
        "capability": row["capability"],
        "topic": row["topic"],
        "allowed": bool(row["allowed"]),
        "version": row["version"],
        "updated_at": row["updated_at"],
    }


def relationship_public(row: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": row["id"],
        "senior_id": row["senior_id"],
        "caregiver_id": row["caregiver_id"],
        "status": row["status"],
        "created_at": row["created_at"],
        "accepted_at": row["accepted_at"],
        "revoked_at": row["revoked_at"],
    }


def memory_public(row: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": row["id"],
        "fact": row["fact"],
        "approval_state": row["approval_state"],
        "approved_at": row["approved_at"],
        "created_at": row["created_at"],
    }


def notification_public(row: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": row["id"],
        "kind": row["kind"],
        "title": row["title"],
        "body": row["body"],
        "read_at": row["read_at"],
        "created_at": row["created_at"],
    }
