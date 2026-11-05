from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, Field

from ..auth import issue_token
from ..errors import not_found, unauthorized
from ..models import me_payload
from .deps import current_user, get_context

router = APIRouter(tags=["auth"])


class DevLoginBody(BaseModel):
    user_id: int = Field(ge=1)


@router.post("/dev/login")
def dev_login(body: DevLoginBody, request: Request) -> dict[str, Any]:
    ctx = request.app.state.ctx
    if ctx.settings.env == "production":
        raise not_found("Endpoint disabled")
    row = ctx.db.query_one("SELECT id, role FROM users WHERE id = ?", (body.user_id,))
    if row is None:
        raise unauthorized("Unknown demo user")
    token, _ = issue_token(ctx.settings, row["id"], row["role"], ctx.clock)
    return {
        "access_token": token,
        "token_type": "bearer",
        "expires_in": ctx.settings.token_ttl_seconds,
    }


@router.get("/me")
def me(
    user: dict[str, Any] = Depends(current_user),
    ctx=Depends(get_context),
) -> dict[str, Any]:
    row = ctx.db.query_one("SELECT * FROM users WHERE id = ?", (user["id"],))
    senior_id = None
    relationship_status = None
    if user["role"] == "senior":
        senior_id = user["id"]
    else:
        relationship = ctx.db.query_one(
            "SELECT senior_id, status FROM relationships WHERE caregiver_id = ? "
            "ORDER BY id DESC LIMIT 1",
            (user["id"],),
        )
        if relationship:
            senior_id = relationship["senior_id"]
            relationship_status = relationship["status"]
    return me_payload(row, senior_id, relationship_status)
