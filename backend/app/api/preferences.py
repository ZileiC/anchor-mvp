"""Preferences read/patch endpoints (SPEC §6.1)."""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Body, Depends

from ..models import preferences_public
from .deps import get_context, require_senior

router = APIRouter(tags=["preferences"])


@router.get("/preferences")
def get_preferences(user: dict = Depends(require_senior), ctx=Depends(get_context)) -> dict:
    row = ctx.preferences.get_or_create(int(user["id"]))
    return preferences_public(row)


@router.patch("/preferences")
def patch_preferences(
    updates: dict[str, Any] = Body(...),
    user: dict = Depends(require_senior),
    ctx=Depends(get_context),
) -> dict:
    row = ctx.preferences.patch(int(user["id"]), updates)
    return preferences_public(row)
