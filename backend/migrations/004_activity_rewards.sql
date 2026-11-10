-- Encouragement reward for answering an activity correctly.
--
-- Product decision (2026-11-10, teacher feedback): a correct answer adds one
-- flower; a wrong answer never subtracts, never shows the word "wrong", and the
-- card keeps teaching instead of scoring.
--
-- This is encouragement, NOT a cognitive assessment: one counter per senior,
-- no levels, no rankings, nothing returned to any other user. The activity pack
-- is companionship material, and the API never calls this a score.
CREATE TABLE IF NOT EXISTS activity_rewards (
    senior_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    flowers INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL
);
