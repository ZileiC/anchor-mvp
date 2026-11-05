"""Proactive check-in endpoints (SPEC §6.2)."""

from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel

from .deps import get_context, require_senior

router = APIRouter(tags=["checkins"])


class AttemptIn(BaseModel):
    device_id: Optional[str] = None
    outcome: str


@router.get("/checkins/eligibility")
def eligibility(
    device_id: Optional[str] = Query(default=None),
    user: dict = Depends(require_senior),
    ctx=Depends(get_context),
) -> dict:
    return ctx.checkins.eligibility(int(user["id"]), device_id)


@router.post("/checkins/attempts")
def attempt(
    body: AttemptIn,
    user: dict = Depends(require_senior),
    ctx=Depends(get_context),
) -> dict:
    return ctx.checkins.attempt(int(user["id"]), body.device_id, body.outcome)


@router.get("/checkins/schedule")
def schedule(user: dict = Depends(require_senior), ctx=Depends(get_context)) -> dict:
    return ctx.checkins.schedule(int(user["id"]))
