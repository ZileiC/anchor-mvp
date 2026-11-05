"""Memory lifecycle and retrieval (SPEC §6.4).

Facts are proposed by the older adult, approved by them, and only approved facts
ever reach a prompt. Deletion is a hard delete plus an audit row that carries no
memory text.
"""

from __future__ import annotations

from typing import Any, Optional

from . import audit
from .clock import Clock, iso_utc
from .consent import ConsentService
from .db import Database
from .errors import AppError, validation_error

MIN_FACT_LENGTH = 3
MAX_FACT_LENGTH = 200
RETRIEVAL_LIMIT = 5


def _overlap(a: str, b: str) -> int:
    best = 0
    for i in range(len(a)):
        for j in range(i + best + 1, len(a) + 1):
            if a[i:j] in b:
                best = j - i
            else:
                break
    return best


class MemoryService:
    def __init__(self, db: Database, clock: Clock, consent: Optional[ConsentService] = None) -> None:
        self.db = db
        self.clock = clock
        self.consent = consent or ConsentService(db, clock)

    # -- queries ----------------------------------------------------------
    def list_for(self, senior_id: int) -> list[dict[str, Any]]:
        return self.db.query(
            "SELECT * FROM memories WHERE senior_id = ? AND approval_state != 'deleted' "
            "ORDER BY id",
            (senior_id,),
        )

    def approved(self, senior_id: int) -> list[dict[str, Any]]:
        return self.db.query(
            "SELECT * FROM memories WHERE senior_id = ? AND approval_state = 'approved' "
            "ORDER BY approved_at DESC, id DESC",
            (senior_id,),
        )

    def get_owned(self, memory_id: int, senior_id: int) -> dict[str, Any]:
        row = self.db.query_one(
            "SELECT * FROM memories WHERE id = ? AND senior_id = ?",
            (memory_id, senior_id),
        )
        if row is None or row["approval_state"] == "deleted":
            raise AppError("not_found", "Not found.")
        return row

    # -- mutations --------------------------------------------------------
    def propose(
        self, senior_id: int, fact: Any, source_ref: Optional[str] = None
    ) -> dict[str, Any]:
        self.consent.require(senior_id, "save_memory")
        if not isinstance(fact, str):
            raise validation_error("fact must be a string")
        cleaned = fact.strip()
        if not MIN_FACT_LENGTH <= len(cleaned) <= MAX_FACT_LENGTH:
            raise validation_error(
                f"fact must be {MIN_FACT_LENGTH}-{MAX_FACT_LENGTH} characters"
            )
        now = iso_utc(self.clock.now())
        memory_id = self.db.insert(
            "INSERT INTO memories(senior_id, fact, approval_state, source_ref, created_at) "
            "VALUES (?,?, 'proposed', ?, ?)",
            (senior_id, cleaned, source_ref, now),
        )
        return self.db.query_one("SELECT * FROM memories WHERE id = ?", (memory_id,))

    def approve(self, memory_id: int, senior_id: int) -> dict[str, Any]:
        row = self.get_owned(memory_id, senior_id)
        if row["approval_state"] == "approved":
            return row
        now = iso_utc(self.clock.now())
        self.db.execute(
            "UPDATE memories SET approval_state = 'approved', approved_at = ? WHERE id = ?",
            (now, memory_id),
        )
        audit.write(self.db, self.clock, senior_id, "memory_approved", "memory", memory_id)
        return self.db.query_one("SELECT * FROM memories WHERE id = ?", (memory_id,))

    def delete(self, memory_id: int, senior_id: int) -> dict[str, Any]:
        row = self.get_owned(memory_id, senior_id)
        with self.db.tx() as conn:
            conn.execute("DELETE FROM memories WHERE id = ?", (memory_id,))
        audit.write(self.db, self.clock, senior_id, "memory_deleted", "memory", memory_id)
        return {"id": row["id"], "deleted": True}

    # -- retrieval --------------------------------------------------------
    def retrieve(
        self,
        senior_id: int,
        utterance: str,
        interests: Optional[list[str]] = None,
        limit: int = RETRIEVAL_LIMIT,
    ) -> list[dict[str, Any]]:
        """Approved memories, ranked by keyword overlap then recency, max ``limit``."""
        memories = self.approved(senior_id)
        if not memories:
            return []
        interests = interests or []
        utterance = utterance or ""
        scored: list[tuple[int, int, dict[str, Any]]] = []
        for order, memory in enumerate(memories):
            fact = str(memory["fact"])
            score = _overlap(fact, utterance)
            for interest in interests:
                if interest and interest in fact:
                    score += 2
            scored.append((score, -order, memory))
        scored.sort(key=lambda item: (item[0], item[1]), reverse=True)
        return [memory for _, _, memory in scored[:limit]]
