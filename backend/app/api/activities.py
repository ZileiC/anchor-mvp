"""Activity endpoints (SPEC §6.5)."""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from .deps import get_context, require_senior

router = APIRouter(tags=["activities"])


class ActivitySessionIn(BaseModel):
    activity_id: str
    completed: bool
    duration_seconds: int


@router.get("/activities")
def list_activities(user: dict = Depends(require_senior), ctx=Depends(get_context)) -> dict:
    return ctx.activities.for_senior(int(user["id"]))


@router.post("/activity-sessions")
def record_activity_session(
    body: ActivitySessionIn,
    user: dict = Depends(require_senior),
    ctx=Depends(get_context),
) -> dict[str, Any]:
    return ctx.activities.record_session(
        int(user["id"]), body.activity_id, body.completed, body.duration_seconds
    )
