"""Conversation session endpoints (SPEC §6.3)."""

from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from ..errors import AppError
from .deps import current_user, get_context, require_senior

router = APIRouter(tags=["sessions"])


class SessionIn(BaseModel):
    origin: str = "voluntary"
    device_id: Optional[str] = None


class TurnIn(BaseModel):
    text: Optional[str] = None
    audio_b64: Optional[str] = None
    audio_mime: Optional[str] = None


@router.post("/sessions")
def open_session(
    body: SessionIn = SessionIn(),
    user: dict = Depends(require_senior),
    ctx=Depends(get_context),
) -> dict:
    return ctx.conversation.open_session(user, body.origin, body.device_id)


@router.get("/sessions/{session_id}")
def get_session(
    session_id: str,
    user: dict = Depends(current_user),
    ctx=Depends(get_context),
) -> dict:
    if user["role"] != "senior":
        raise AppError("caregiver_scope_denied", "Conversations are private.")
    return ctx.conversation.session_view(session_id, int(user["id"]))


@router.post("/sessions/{session_id}/turns")
def add_turn(
    session_id: str,
    body: TurnIn,
    user: dict = Depends(require_senior),
    ctx=Depends(get_context),
) -> dict:
    return ctx.conversation.turn(
        user,
        session_id,
        text=body.text,
        audio_b64=body.audio_b64,
        audio_mime=body.audio_mime,
    )


@router.post("/sessions/{session_id}/stop")
def stop_session(
    session_id: str,
    user: dict = Depends(require_senior),
    ctx=Depends(get_context),
) -> dict:
    return ctx.conversation.stop(session_id, int(user["id"]))
