"""Digest endpoints (SPEC §6.6).

Seniors see their own digests in every state (preview before approval). A
caregiver sees only approved/delivered updates for the linked senior, and every
item is re-filtered against the current relationship and ``share_topic`` consents.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from .deps import current_user, get_context, require_senior

router = APIRouter(tags=["digests"])


class DigestItemIn(BaseModel):
    topic: str
    text: str
    evidence_ids: list[int] = Field(default_factory=list)


class DigestPatchIn(BaseModel):
    items: list[DigestItemIn] = Field(default_factory=list)


@router.get("/digests")
def list_digests(user: dict = Depends(current_user), ctx=Depends(get_context)) -> dict:
    if user["role"] == "senior":
        return ctx.digests.list_for_senior(int(user["id"]))
    return ctx.digests.list_for_caregiver(int(user["id"]))


@router.get("/digests/{digest_id}")
def get_digest(
    digest_id: int,
    user: dict = Depends(current_user),
    ctx=Depends(get_context),
) -> dict:
    return ctx.digests.view_for(user, digest_id)


@router.patch("/digests/{digest_id}")
def patch_digest(
    digest_id: int,
    body: DigestPatchIn,
    user: dict = Depends(require_senior),
    ctx=Depends(get_context),
) -> dict:
    items = [item.model_dump() for item in body.items]
    return ctx.digests.patch(digest_id, int(user["id"]), items)


@router.post("/digests/{digest_id}/approve")
def approve_digest(
    digest_id: int,
    user: dict = Depends(require_senior),
    ctx=Depends(get_context),
) -> dict:
    return ctx.digests.approve(digest_id, int(user["id"]))
