"""Notification inbox endpoints (SPEC §6.6).

Rows are generic by construction; a user only ever reads their own inbox.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends

from .deps import current_user, get_context

router = APIRouter(tags=["notifications"])


@router.get("/notifications")
def list_notifications(user: dict = Depends(current_user), ctx=Depends(get_context)) -> dict:
    return {"items": ctx.notifications.list_for(int(user["id"]))}


@router.patch("/notifications/{notification_id}")
def mark_notification_read(
    notification_id: int,
    user: dict = Depends(current_user),
    ctx=Depends(get_context),
) -> dict:
    return ctx.notifications.mark_read(notification_id, int(user["id"]))
