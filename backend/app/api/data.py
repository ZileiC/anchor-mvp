"""Data-rights endpoint: the older adult deletes everything (SPEC §6.7).

Deletion is immediate and irreversible. The response reports per-table counts so
the app can show an honest confirmation; the audit trail records that a deletion
happened, never what was deleted.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from ..errors import validation_error
from .deps import get_context, require_senior

router = APIRouter(tags=["data"])


class DeleteDataIn(BaseModel):
    confirm: bool = False


@router.delete("/data")
def delete_data(
    body: DeleteDataIn,
    user: dict = Depends(require_senior),
    ctx=Depends(get_context),
) -> dict:
    if body.confirm is not True:
        raise validation_error("Set confirm=true to delete your data.")
    deleted = ctx.data_rights.delete(int(user["id"]))
    return {"deleted": deleted}
