"""Contact and call-initiation endpoints (SPEC §6.6).

A senior sees and calls their own saved contacts. A caregiver may see and call the
linked, accepted senior's contacts so the digest's "Call to check in" button works;
any other household is denied.
"""

from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from .deps import current_user, get_context

router = APIRouter(tags=["contacts"])


class ContactActionIn(BaseModel):
    contact_id: int
    confirmed: Optional[bool] = None


@router.get("/contacts")
def list_contacts(user: dict = Depends(current_user), ctx=Depends(get_context)) -> dict:
    return {"items": ctx.contacts.list_for(user)}


@router.post("/contact-actions")
def create_contact_action(
    body: ContactActionIn,
    user: dict = Depends(current_user),
    ctx=Depends(get_context),
) -> dict:
    return ctx.contacts.initiate(user, body.contact_id, body.confirmed)
