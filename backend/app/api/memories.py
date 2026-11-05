"""Memory endpoints (SPEC §6.4)."""

from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from ..models import memory_public
from .deps import get_context, require_senior

router = APIRouter(tags=["memories"])


class MemoryIn(BaseModel):
    fact: str
    source_ref: Optional[str] = None


@router.get("/memories")
def list_memories(user: dict = Depends(require_senior), ctx=Depends(get_context)) -> dict:
    rows = ctx.memory.list_for(int(user["id"]))
    return {"items": [memory_public(row) for row in rows]}


@router.post("/memories")
def propose_memory(
    body: MemoryIn,
    user: dict = Depends(require_senior),
    ctx=Depends(get_context),
) -> dict:
    row = ctx.memory.propose(int(user["id"]), body.fact, body.source_ref)
    return memory_public(row)


@router.post("/memories/{memory_id}/approve")
def approve_memory(
    memory_id: int,
    user: dict = Depends(require_senior),
    ctx=Depends(get_context),
) -> dict:
    return memory_public(ctx.memory.approve(memory_id, int(user["id"])))


@router.delete("/memories/{memory_id}")
def delete_memory(
    memory_id: int,
    user: dict = Depends(require_senior),
    ctx=Depends(get_context),
) -> dict:
    return ctx.memory.delete(memory_id, int(user["id"]))
