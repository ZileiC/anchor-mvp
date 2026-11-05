from __future__ import annotations

from typing import Any

from fastapi import APIRouter

router = APIRouter(tags=["health"])


@router.get("/health")
def health() -> dict[str, Any]:
    from ..main import OFFLINE_CAPABILITIES, VERSION

    return {
        "status": "ok",
        "version": VERSION,
        "offline_capabilities": OFFLINE_CAPABILITIES,
    }
