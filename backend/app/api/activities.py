"""Activity endpoints (SPEC §6.5)."""

from __future__ import annotations

from typing import Any, Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel, StrictBool

from .deps import get_context, require_senior

router = APIRouter(tags=["activities"])


class ActivitySessionIn(BaseModel):
    activity_id: str
    completed: bool
    duration_seconds: int
    # Was the answer right? Omitted means "not a graded card" (memory cards).
    # StrictBool on purpose: pydantic would otherwise coerce "yes"/1 into True
    # and hand out flowers for a typo. Only a real JSON boolean earns one.
    correct: Optional[StrictBool] = None


@router.get("/activities")
def list_activities(user: dict = Depends(require_senior), ctx=Depends(get_context)) -> dict:
    return ctx.activities.for_senior(int(user["id"]))


@router.get("/rewards")
def rewards(user: dict = Depends(require_senior), ctx=Depends(get_context)) -> dict:
    """The senior's encouragement counter (flowers), never a score or a level."""
    return {"flowers": ctx.activities.flowers(int(user["id"]))}


@router.post("/activity-sessions")
def record_activity_session(
    body: ActivitySessionIn,
    user: dict = Depends(require_senior),
    ctx=Depends(get_context),
) -> dict[str, Any]:
    return ctx.activities.record_session(
        int(user["id"]),
        body.activity_id,
        body.completed,
        body.duration_seconds,
        correct=body.correct,
    )
