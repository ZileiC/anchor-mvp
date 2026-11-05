"""FastAPI dependency helpers."""
from __future__ import annotations

from typing import Any

from fastapi import Depends, Request

from ..auth import get_current_user
from ..errors import forbidden


def get_context(request: Request):
    return request.app.state.ctx


def current_user(user: dict[str, Any] = Depends(get_current_user)) -> dict[str, Any]:
    return user


def require_senior(user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
    if user["role"] != "senior":
        raise forbidden("This action belongs to the older adult.")
    return user


def require_caregiver(user: dict[str, Any] = Depends(current_user)) -> dict[str, Any]:
    if user["role"] != "caregiver":
        raise forbidden("This action belongs to a family caregiver.")
    return user
