"""Digest endpoints (SPEC §6.6).

Seniors see their own digests in every state (preview before approval). A
caregiver sees only approved/delivered updates for the linked senior, and every
item is re-filtered against the current relationship and ``share_topic`` consents.
"""

from __future__ import annotations

from datetime import timedelta

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from .deps import current_user, get_context, require_senior
from .. import audit
from ..clock import local_now
from ..errors import AppError

router = APIRouter(tags=["digests"])


class DigestItemIn(BaseModel):
    topic: str
    text: str
    evidence_ids: list[int] = Field(default_factory=list)


class DigestPatchIn(BaseModel):
    items: list[DigestItemIn] = Field(default_factory=list)


@router.post("/digests/generate")
def generate_digest(user: dict = Depends(require_senior), ctx=Depends(get_context)) -> dict:
    """Prepare the last completed local ISO week; never invent demo observations."""
    today = local_now(ctx.clock, user["timezone"]).date()
    end = today - timedelta(days=today.weekday())
    start = end - timedelta(days=7)
    digest = ctx.digests.ensure_weekly_digest(int(user["id"]), start.isoformat(), end.isoformat())
    audit.write(ctx.db, ctx.clock, int(user["id"]), "digest_generation_requested", "digest", digest["id"])
    return digest


@router.post("/digests/{digest_id}/publish")
def publish_digest(digest_id: int, user: dict = Depends(require_senior), ctx=Depends(get_context)) -> dict:
    """Explicit senior approval and immediate in-app delivery, without a worker.

    The same delivery service rechecks permissions and suppresses duplicates.
    Its queued worker retry is safe if the client disconnects after approval.
    """
    senior_id = int(user["id"])
    row = ctx.digests.get_owned(digest_id, senior_id)
    if row["status"] == "delivered":
        return ctx.digests.view_for(user, digest_id)
    if row["status"] not in ("draft", "awaiting_senior_approval", "approved"):
        raise AppError("conflict", "This update cannot be shared.")
    if not ctx.db.query_one(
        "SELECT id FROM relationships WHERE senior_id = ? AND status = 'accepted'", (senior_id,)
    ):
        raise AppError("conflict", "Connect a family member before sharing.")
    # Every topic in the draft must still have permission when publishing.
    visible = ctx.digests.view_for(user, digest_id)
    if not visible["items"] or any(
        not ctx.consent.is_allowed(senior_id, "share_topic", item["topic"])
        for item in visible["items"]
    ):
        raise AppError("conflict", "Sharing choices changed. Review the update before sharing.")
    if row["status"] == "draft":
        ctx.digests.patch(digest_id, senior_id, visible["items"])
    if row["status"] != "approved":
        ctx.digests.approve(digest_id, senior_id)
    result = ctx.digests.deliver(digest_id)
    if not result["delivered"] and ctx.digests.get_owned(digest_id, senior_id)["status"] != "delivered":
        raise AppError("conflict", "The update could not be shared. Check your sharing choices.")
    return ctx.digests.view_for(user, digest_id)


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
