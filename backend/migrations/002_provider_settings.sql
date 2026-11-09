-- Runtime-selectable provider configuration (LLM + ASR), edited from Settings.
--
-- One singleton row (id = 1). A section is usable only when both a base URL and
-- an API key are present; the URL and key are never returned in full by the API.
--
-- SECURITY LIMITATION: the API keys are stored as plaintext in the local SQLite
-- file because this is a self-hosted single-machine demo. Anyone who can read
-- anchor.db can read the keys. Do not use a shared or production database, and
-- do not copy this file in bug reports/screenshots. A production deployment must
-- move these secrets to the OS keychain or a managed secret store.

CREATE TABLE IF NOT EXISTS provider_settings (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    llm_base_url TEXT,
    llm_api_key TEXT,
    llm_model TEXT,
    asr_base_url TEXT,
    asr_api_key TEXT,
    asr_model TEXT,
    updated_at TEXT
);
