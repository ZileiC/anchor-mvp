-- Activities offered inside a normal conversation.
--
-- Product decision (2026-11-10): Play stops being a separate world. A chat turn
-- may carry one activity; this table is the per-session memory of what was
-- already offered, so an item is never offered twice in one conversation and
-- two offers are never back to back.
--
-- Deliberately NOT the rotation: `activity_rotation` is advanced only when the
-- senior actually answers (POST /activity-sessions), so an ignored offer changes
-- nothing. `turn_number` is the 1-based count of senior turns at offer time; the
-- offer rule needs it ("not in the last two turns") without re-counting rows that
-- Stop purges. The row carries no speech, only ids.
CREATE TABLE IF NOT EXISTS activity_offers (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    senior_id INTEGER NOT NULL REFERENCES users(id),
    activity_id TEXT NOT NULL,
    turn_number INTEGER NOT NULL,
    offered_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_activity_offers_session ON activity_offers(session_id);
