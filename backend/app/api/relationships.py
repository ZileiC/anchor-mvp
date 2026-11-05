"""Family links, invitations and schedule proposals (SPEC §6.1)."""

from __future__ import annotations

import json
from typing import Any

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from ..errors import AppError
from ..models import relationship_public
from .deps import current_user, get_context, require_caregiver, require_senior

router = APIRouter(tags=["relationships"])


class InvitationIn(BaseModel):
    expires_in_hours: int = 24


class AcceptIn(BaseModel):
    token: str


class ProposalIn(BaseModel):
    payload: dict[str, Any]


def _relationship_payload(row: dict[str, Any]) -> dict[str, Any]:
    payload = relationship_public(row)
    payload["counterpart_id"] = row.get("counterpart_id")
    payload["counterpart_name"] = row.get("counterpart_name")
    payload["counterpart_locale"] = row.get("counterpart_locale")
    return payload


def _proposal_payload(row: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": row["id"],
        "senior_id": row["senior_id"],
        "caregiver_id": row["caregiver_id"],
        "payload": row.get("payload"),
        "status": row["status"],
        "created_at": row["created_at"],
        "decided_at": row["decided_at"],
        "counterpart_name": row.get("counterpart_name"),
    }


@router.post("/invitations")
def create_invitation(
    body: InvitationIn = InvitationIn(),
    user: dict = Depends(require_senior),
    ctx=Depends(get_context),
) -> dict:
    return ctx.relationships.create_invitation(int(user["id"]), body.expires_in_hours)


@router.post("/invitations/accept")
def accept_invitation(
    body: AcceptIn,
    user: dict = Depends(require_caregiver),
    ctx=Depends(get_context),
) -> dict:
    return ctx.relationships.accept_invitation(int(user["id"]), body.token)


@router.get("/relationships")
def list_relationships(
    user: dict = Depends(current_user),
    ctx=Depends(get_context),
) -> dict:
    rows = ctx.relationships.list_for(user)
    return {"items": [_relationship_payload(row) for row in rows]}


@router.post("/relationships/{relationship_id}/approve")
def approve_relationship(
    relationship_id: int,
    user: dict = Depends(require_senior),
    ctx=Depends(get_context),
) -> dict:
    row = ctx.relationships.approve(relationship_id, int(user["id"]))
    row = {**row, "counterpart_id": row["caregiver_id"]}
    return _relationship_payload(row)


@router.delete("/relationships/{relationship_id}")
def revoke_relationship(
    relationship_id: int,
    user: dict = Depends(require_senior),
    ctx=Depends(get_context),
) -> dict:
    return ctx.relationships.revoke(relationship_id, int(user["id"]))


@router.post("/schedule-proposals")
def create_proposal(
    body: ProposalIn,
    user: dict = Depends(require_caregiver),
    ctx=Depends(get_context),
) -> dict:
    link = ctx.relationships.linked_senior(int(user["id"]))
    if link is None:
        raise AppError("relationship_inactive", "This family connection is not active.")
    row = ctx.schedule_proposals.create(
        int(user["id"]), int(link["senior_id"]), body.payload
    )
    return _proposal_payload({**row, "payload": body.payload})


@router.get("/schedule-proposals")
def list_proposals(
    user: dict = Depends(current_user),
    ctx=Depends(get_context),
) -> dict:
    rows = ctx.schedule_proposals.list_for(user)
    return {"items": [_proposal_payload(row) for row in rows]}


@router.post("/schedule-proposals/{proposal_id}/approve")
def approve_proposal(
    proposal_id: int,
    user: dict = Depends(require_senior),
    ctx=Depends(get_context),
) -> dict:
    row = ctx.schedule_proposals.approve(proposal_id, int(user["id"]))
    payload = json.loads(row["payload_json"])
    return _proposal_payload({**row, "payload": payload})
