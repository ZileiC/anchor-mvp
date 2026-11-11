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


def require_setup_access(
    request: Request,
    user: dict[str, Any] = Depends(current_user),
) -> dict[str, Any]:
    """Who may configure the AI providers.

    Decided 2026-11-11: which model and which speech service the appliance talks
    to is **device configuration**, not the older adult's private information.
    The family sets it up with them, on the phone, at first run — the older
    adult's own privacy is about consents, memories, conversations and what gets
    shared, and those stay senior-only.

    So both roles may read, write and probe the providers, but a caregiver has to
    actually be connected: an account with no accepted link is a stranger.
    """
    if user["role"] == "senior":
        return user
    if user["role"] != "caregiver":
        raise forbidden("This action belongs to the older adult or their family.")
    if get_context(request).relationships.linked_senior(int(user["id"])) is None:
        raise forbidden("This family connection is not active.")
    return user
