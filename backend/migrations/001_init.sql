PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    role TEXT NOT NULL CHECK (role IN ('senior', 'caregiver')),
    display_name TEXT NOT NULL,
    auth_subject TEXT NOT NULL UNIQUE,
    timezone TEXT NOT NULL DEFAULT 'Asia/Shanghai',
    locale TEXT NOT NULL DEFAULT 'zh-CN',
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS relationships (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    senior_id INTEGER NOT NULL REFERENCES users(id),
    caregiver_id INTEGER NOT NULL REFERENCES users(id),
    status TEXT NOT NULL CHECK (status IN ('pending', 'accepted', 'revoked')),
    created_at TEXT NOT NULL,
    accepted_at TEXT,
    revoked_at TEXT,
    UNIQUE (senior_id, caregiver_id)
);
CREATE INDEX IF NOT EXISTS idx_relationships_senior ON relationships(senior_id);

CREATE TABLE IF NOT EXISTS invitations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    senior_id INTEGER NOT NULL REFERENCES users(id),
    token_hash TEXT NOT NULL UNIQUE,
    expires_at TEXT NOT NULL,
    used_at TEXT,
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS preferences (
    senior_id INTEGER PRIMARY KEY REFERENCES users(id),
    greeting_start TEXT NOT NULL DEFAULT '09:00',
    greeting_end TEXT NOT NULL DEFAULT '11:00',
    quiet_start TEXT NOT NULL DEFAULT '21:00',
    quiet_end TEXT NOT NULL DEFAULT '08:00',
    daily_cap INTEGER NOT NULL DEFAULT 1 CHECK (daily_cap IN (0, 1)),
    paused INTEGER NOT NULL DEFAULT 0,
    snoozed_until TEXT,
    voice_pace TEXT NOT NULL DEFAULT 'slow' CHECK (voice_pace IN ('slow', 'normal')),
    short_replies INTEGER NOT NULL DEFAULT 1,
    language TEXT NOT NULL DEFAULT 'zh-CN',
    interests TEXT NOT NULL DEFAULT '[]',
    observation_topics TEXT NOT NULL DEFAULT '["participation","activities","mood","meals","wellbeing"]',
    designated_device_id TEXT,
    digest_retention_days INTEGER NOT NULL DEFAULT 365,
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS consents (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    senior_id INTEGER NOT NULL REFERENCES users(id),
    capability TEXT NOT NULL CHECK (capability IN
        ('cloud_processing', 'proactive_invitations', 'save_memory', 'record_observations', 'share_topic')),
    topic TEXT NOT NULL DEFAULT '',
    allowed INTEGER NOT NULL DEFAULT 0,
    version INTEGER NOT NULL,
    updated_at TEXT NOT NULL,
    UNIQUE (senior_id, capability, topic)
);

CREATE TABLE IF NOT EXISTS consent_state (
    senior_id INTEGER PRIMARY KEY REFERENCES users(id),
    version INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS memories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    senior_id INTEGER NOT NULL REFERENCES users(id),
    fact TEXT NOT NULL,
    approval_state TEXT NOT NULL CHECK (approval_state IN ('proposed', 'approved', 'deleted')),
    approved_at TEXT,
    source_ref TEXT,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_memories_senior ON memories(senior_id, approval_state);

CREATE TABLE IF NOT EXISTS contacts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    senior_id INTEGER NOT NULL REFERENCES users(id),
    label TEXT NOT NULL,
    phone TEXT NOT NULL,
    is_family INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS sessions (
    id TEXT PRIMARY KEY,
    senior_id INTEGER NOT NULL REFERENCES users(id),
    origin TEXT NOT NULL CHECK (origin IN ('voluntary', 'proactive')),
    state TEXT NOT NULL CHECK (state IN ('active', 'stopped', 'ended')),
    cancellation_token TEXT NOT NULL,
    started_at TEXT NOT NULL,
    ended_at TEXT
);

CREATE TABLE IF NOT EXISTS turns (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL REFERENCES sessions(id),
    role TEXT NOT NULL CHECK (role IN ('senior', 'anchor')),
    text TEXT NOT NULL,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_turns_session ON turns(session_id);

CREATE TABLE IF NOT EXISTS observations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    senior_id INTEGER NOT NULL REFERENCES users(id),
    topic TEXT NOT NULL CHECK (topic IN ('participation', 'activities', 'mood', 'meals', 'wellbeing')),
    event_date TEXT NOT NULL,
    evidence TEXT NOT NULL,
    source_ref TEXT,
    consent_version INTEGER NOT NULL,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_observations_senior_date ON observations(senior_id, event_date);

CREATE TABLE IF NOT EXISTS activity_rotation (
    senior_id INTEGER NOT NULL REFERENCES users(id),
    activity_type TEXT NOT NULL CHECK (activity_type IN ('trivia', 'story', 'memory')),
    last_index INTEGER NOT NULL DEFAULT -1,
    updated_at TEXT NOT NULL,
    PRIMARY KEY (senior_id, activity_type)
);

CREATE TABLE IF NOT EXISTS digests (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    senior_id INTEGER NOT NULL REFERENCES users(id),
    period_start TEXT NOT NULL,
    period_end TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN
        ('draft', 'awaiting_senior_approval', 'approved', 'delivered', 'cancelled', 'insufficient_data')),
    items_json TEXT NOT NULL DEFAULT '[]',
    consent_version INTEGER NOT NULL,
    edited_by TEXT,
    edited_at TEXT,
    notification_sent_at TEXT,
    delivered_at TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    UNIQUE (senior_id, period_start)
);

CREATE TABLE IF NOT EXISTS jobs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    job_type TEXT NOT NULL,
    payload_json TEXT NOT NULL DEFAULT '{}',
    due_at TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('pending', 'running', 'done', 'failed', 'dead')),
    attempts INTEGER NOT NULL DEFAULT 0,
    max_attempts INTEGER NOT NULL DEFAULT 5,
    lease_expires_at TEXT,
    idempotency_key TEXT NOT NULL UNIQUE,
    last_error TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_jobs_status_due ON jobs(status, due_at);

CREATE TABLE IF NOT EXISTS schedule_proposals (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    senior_id INTEGER NOT NULL REFERENCES users(id),
    caregiver_id INTEGER NOT NULL REFERENCES users(id),
    payload_json TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
    created_at TEXT NOT NULL,
    decided_at TEXT
);

CREATE TABLE IF NOT EXISTS contact_actions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    senior_id INTEGER NOT NULL REFERENCES users(id),
    actor_user_id INTEGER NOT NULL REFERENCES users(id),
    contact_id INTEGER NOT NULL REFERENCES contacts(id),
    phone TEXT NOT NULL,
    initiated_at TEXT NOT NULL,
    confirmed_at TEXT
);

CREATE TABLE IF NOT EXISTS checkin_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    senior_id INTEGER NOT NULL REFERENCES users(id),
    device_id TEXT NOT NULL,
    local_date TEXT NOT NULL,
    outcome TEXT NOT NULL CHECK (outcome IN ('shown', 'dismissed', 'accepted', 'no_response')),
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_checkin_senior_date ON checkin_events(senior_id, local_date);

CREATE TABLE IF NOT EXISTS notifications (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id),
    kind TEXT NOT NULL,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    read_at TEXT,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id, read_at);

CREATE TABLE IF NOT EXISTS audit_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    actor_user_id INTEGER,
    action TEXT NOT NULL,
    target_type TEXT NOT NULL,
    target_id TEXT,
    outcome TEXT NOT NULL,
    created_at TEXT NOT NULL
);
