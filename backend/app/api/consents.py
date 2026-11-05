"""Consent read/update endpoints (SPEC §5, §6.1)."""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from .deps import get_context, require_senior

router = APIRouter(tags=["consents"])


class ConsentChange(BaseModel):
    capability: str
    topic: str = ""
    allowed: bool


class ConsentUpdateIn(BaseModel):
    base_version: int
    changes: list[ConsentChange] = Field(default_factory=list)


@router.get("/consents")
def get_consents(user: dict = Depends(require_senior), ctx=Depends(get_context)) -> dict:
    return ctx.consent.snapshot(int(user["id"]))


@router.put("/consents")
def put_consents(
    body: ConsentUpdateIn,
    user: dict = Depends(require_senior),
    ctx=Depends(get_context),
) -> dict:
    changes: list[dict[str, Any]] = [change.model_dump() for change in body.changes]
    return ctx.consent.update(int(user["id"]), body.base_version, changes, actor_user_id=int(user["id"]))
