# Anchor MVP — Implementation Contract (SPEC)

**Authority.** `../Anchor_Software_Design_and_MVP_Guide.md` is the product requirement document.
This file freezes the *engineering contract* (layout, schema, API, rules, test IDs) that the
implementation must satisfy. If this file and the guide ever disagree, the guide wins; record the
resolution in `DECISIONS.md` and change this file in the same commit.

**Scope.** One Flutter application (older-adult mode + caregiver mode), one FastAPI backend, one
SQLite database, one persistent-job worker, one curated content pack. Modules F1–F4, sub-needs
S1–S12, all §8 acceptance measures and all §8 required failure tests.

**Status vocabulary.** `TODO` / `IN PROGRESS` / `DONE (evidence: …)`. Only `scripts/verify.ps1`
exiting 0 may justify `DONE`.

---

## 1. Repository layout (required)

```text
anchor/
  README.md                        # quickstart, demo script, honest limitations
  SPEC.md                          # this file (do not rewrite contracts casually)
  BUILD_PLAN.md                    # milestone ledger the loop works through
  DECISIONS.md                     # append-only engineering decisions log
  .gitignore
  content/activities.json          # curated activity pack (trilingual-ready)
  backend/
    requirements.txt
    pytest.ini
    app/
      __init__.py
      main.py                      # create_app(settings) -> FastAPI
      config.py                    # Settings from env; test overrides
      clock.py                     # Clock: now() -> datetime (UTC); FakeClock in tests
      db.py                        # connect(), migrate(), tx(), row helpers
      errors.py                    # AppError(code, status, message) + handler
      auth.py                      # token issue/verify, current_user, require_senior/caregiver
      models.py                    # dataclasses + row->dict serializers
      consent.py                   # ConsentService: capabilities, versions, enforcement
      relationships.py             # invite/accept/approve/revoke
      preferences.py               # read/patch, window + quiet-hours validation
      checkins.py                  # eligibility, attempts, schedule
      conversation/
        __init__.py
        commands.py                # deterministic command routing (stop/repeat/play/call)
        orchestrator.py            # turn pipeline + cancellation token
        prompt.py                  # system instruction builder
      providers/
        __init__.py
        base.py                    # ASRAdapter, LLMAdapter, Notifier protocols
        asr_http.py                # OpenAI-compatible /audio/transcriptions
        asr_fake.py                # deterministic transcript for tests
        llm_http.py                # OpenAI-compatible /chat/completions
        llm_rule.py                # offline deterministic dialogue (default)
        notifier.py                # generic notifications, no payloads with health content
      activities/
        __init__.py
        engine.py                  # content load, rotation, session records
      digests/
        __init__.py
        baseline.py                # adequate-data rule + per-topic statistics
        render.py                  # deterministic plain-language items
        language_guard.py          # diagnostic-language detector
        service.py                 # draft/edit/approve/deliver/filter lifecycle
      storage/
        __init__.py
        retention.py               # purge rules, deletion request
      api/
        __init__.py
        deps.py
        auth_routes.py
        relationships.py
        consents.py
        preferences.py
        checkins.py
        sessions.py
        memories.py
        activities.py
        digests.py
        contacts.py
        data.py
        health.py
    migrations/001_init.sql
    worker.py                      # python -m app.worker / python worker.py
    tests/                         # pytest; one file per area + acceptance matrix
  mobile/                          # Flutter app (created by flutter create; keep windows+web+android)
    lib/
      main.dart
      app.dart
      config.dart
      theme.dart
      models/
      services/                    # api_client, credential_store, tts, speech_input, dialer, reminders
      state/                       # app_state, consent_snapshot, session_controller
      screens/                     # senior + caregiver
      widgets/
    test/                          # unit + widget tests
    windows/CMakeLists.txt         # MUST keep the Anchor install-prefix fix (see §13.4)
  docs/
    setup.md
    acceptance-checklist.md
    limitations.md
    measurement.md                 # §8 measurement protocol + forms
  scripts/
    bootstrap.ps1                  # venv + deps + env file + migrate + seed
    run_backend.ps1
    run_worker.ps1
    run_app.ps1                    # flutter run -d windows via ASCII build dir, or web
    build_windows.ps1              # ASCII-path build, copies exe to mobile/dist
    verify.ps1                     # THE gate: backend tests, analyze, flutter test, build
    seed_demo.py                   # deterministic demo data (idempotent)
    eval_wer.py                    # WER evaluator for §8 speech measurement
  DECISIONS.md
```

## 2. Runtime, config, determinism

- Python 3.10+, FastAPI, stdlib `sqlite3`, uvicorn, pytest, httpx. No ORM.
- `Settings` (env, prefix `ANCHOR_`):
  - `ANCHOR_ENV` (`dev`|`test`|`production`; default `dev`)
  - `ANCHOR_SECRET` (HMAC key; default dev-only constant, required non-default in production)
  - `ANCHOR_DB_PATH` (default `backend/data/anchor.db`; `:memory:` supported for tests)
  - `ANCHOR_TIMEZONE` default `Asia/Shanghai`
  - `ANCHOR_ASR_PROVIDER` = `fake`|`http`; `ANCHOR_ASR_URL`, `ANCHOR_ASR_API_KEY`, `ANCHOR_ASR_MODEL`
  - `ANCHOR_LLM_PROVIDER` = `rule`|`http`; `ANCHOR_LLM_URL`, `ANCHOR_LLM_API_KEY`, `ANCHOR_LLM_MODEL`
  - `ANCHOR_TOKEN_TTL_SECONDS` default 86400
  - `ANCHOR_WORKER_INTERVAL_SECONDS` default 60; `ANCHOR_JOB_LEASE_SECONDS` default 120
- **Injected clock** everywhere a schedule is computed: `Clock.now()`; tests replace it.
  No `datetime.now()` / `utcnow()` in business code (only `clock.py`).
- All timestamps stored as ISO-8601 UTC strings with `Z` (or `+00:00`). Local-date decisions always
  go through `ZoneInfo(preferences.timezone)`.
- Provider adapters must be swappable with no business-logic change; tests use fakes via
  `create_app(settings, providers=...)`.
- **Offline/degraded:** every provider failure returns a structured `provider_unavailable` error with
  recovery hints; never a 500 stack trace.

## 3. Data model (migrations/001_init.sql)

All tables `STRICT`-free plain SQLite. `PRAGMA foreign_keys=ON; PRAGMA journal_mode=WAL;` (WAL skipped
for `:memory:`). `CREATE TABLE IF NOT EXISTS`. Add indexes where noted.

```sql
users(id INTEGER PRIMARY KEY AUTOINCREMENT,
      role TEXT NOT NULL CHECK(role IN ('senior','caregiver')),
      display_name TEXT NOT NULL,
      auth_subject TEXT NOT NULL UNIQUE,
      timezone TEXT NOT NULL DEFAULT 'Asia/Shanghai',
      locale TEXT NOT NULL DEFAULT 'zh-CN',
      created_at TEXT NOT NULL);

relationships(id INTEGER PRIMARY KEY AUTOINCREMENT,
      senior_id INTEGER NOT NULL REFERENCES users(id),
      caregiver_id INTEGER NOT NULL REFERENCES users(id),
      status TEXT NOT NULL CHECK(status IN ('pending','accepted','revoked')),
      created_at TEXT NOT NULL, accepted_at TEXT, revoked_at TEXT,
      UNIQUE(senior_id, caregiver_id));

invitations(id INTEGER PRIMARY KEY AUTOINCREMENT,
      senior_id INTEGER NOT NULL REFERENCES users(id),
      token_hash TEXT NOT NULL UNIQUE,
      expires_at TEXT NOT NULL, used_at TEXT, created_at TEXT NOT NULL);

preferences(senior_id INTEGER PRIMARY KEY REFERENCES users(id),
      greeting_start TEXT NOT NULL DEFAULT '09:00',
      greeting_end TEXT NOT NULL DEFAULT '11:00',
      quiet_start TEXT NOT NULL DEFAULT '21:00',
      quiet_end TEXT NOT NULL DEFAULT '08:00',
      daily_cap INTEGER NOT NULL DEFAULT 1 CHECK(daily_cap IN (0,1)),   -- MVP cap: at most 1
      paused INTEGER NOT NULL DEFAULT 0,
      snoozed_until TEXT,
      voice_pace TEXT NOT NULL DEFAULT 'slow' CHECK(voice_pace IN ('slow','normal')),
      short_replies INTEGER NOT NULL DEFAULT 1,
      language TEXT NOT NULL DEFAULT 'zh-CN',
      interests TEXT NOT NULL DEFAULT '[]',           -- JSON array of strings
      observation_topics TEXT NOT NULL DEFAULT '["participation","activities","mood","meals","wellbeing"]',
      designated_device_id TEXT,
      digest_retention_days INTEGER NOT NULL DEFAULT 365,
      updated_at TEXT NOT NULL);

consents(id INTEGER PRIMARY KEY AUTOINCREMENT,
      senior_id INTEGER NOT NULL REFERENCES users(id),
      capability TEXT NOT NULL CHECK(capability IN
        ('cloud_processing','proactive_invitations','save_memory','record_observations','share_topic')),
      topic TEXT NOT NULL DEFAULT '',   -- non-empty only for share_topic
      allowed INTEGER NOT NULL DEFAULT 0,
      version INTEGER NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(senior_id, capability, topic));

consent_state(senior_id INTEGER PRIMARY KEY REFERENCES users(id),
      version INTEGER NOT NULL DEFAULT 1);

memories(id INTEGER PRIMARY KEY AUTOINCREMENT,
      senior_id INTEGER NOT NULL REFERENCES users(id),
      fact TEXT NOT NULL,
      approval_state TEXT NOT NULL CHECK(approval_state IN ('proposed','approved','deleted')),
      approved_at TEXT, source_ref TEXT, created_at TEXT NOT NULL);

contacts(id INTEGER PRIMARY KEY AUTOINCREMENT,
      senior_id INTEGER NOT NULL REFERENCES users(id),
      label TEXT NOT NULL, phone TEXT NOT NULL, is_family INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL);

sessions(id TEXT PRIMARY KEY,               -- uuid4
      senior_id INTEGER NOT NULL REFERENCES users(id),
      origin TEXT NOT NULL CHECK(origin IN ('voluntary','proactive')),
      state TEXT NOT NULL CHECK(state IN ('active','stopped','ended')),
      cancellation_token TEXT NOT NULL,
      started_at TEXT NOT NULL, ended_at TEXT);

turns(id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id TEXT NOT NULL REFERENCES sessions(id),
      role TEXT NOT NULL CHECK(role IN ('senior','anchor')),
      text TEXT NOT NULL, created_at TEXT NOT NULL);  -- purged when session ends

observations(id INTEGER PRIMARY KEY AUTOINCREMENT,
      senior_id INTEGER NOT NULL REFERENCES users(id),
      topic TEXT NOT NULL CHECK(topic IN ('participation','activities','mood','meals','wellbeing')),
      event_date TEXT NOT NULL,             -- YYYY-MM-DD in senior local time
      evidence TEXT NOT NULL,               -- concise, user-sourced text; no inference
      source_ref TEXT,
      consent_version INTEGER NOT NULL,
      created_at TEXT NOT NULL);

activity_rotation(senior_id INTEGER NOT NULL REFERENCES users(id),
      activity_type TEXT NOT NULL CHECK(activity_type IN ('trivia','story','memory')),
      last_index INTEGER NOT NULL DEFAULT -1,
      updated_at TEXT NOT NULL,
      PRIMARY KEY(senior_id, activity_type));

digests(id INTEGER PRIMARY KEY AUTOINCREMENT,
      senior_id INTEGER NOT NULL REFERENCES users(id),
      period_start TEXT NOT NULL,           -- YYYY-MM-DD (Monday, local)
      period_end TEXT NOT NULL,             -- YYYY-MM-DD (exclusive next Monday)
      status TEXT NOT NULL CHECK(status IN
        ('draft','awaiting_senior_approval','approved','delivered','cancelled','insufficient_data')),
      items_json TEXT NOT NULL DEFAULT '[]',
      consent_version INTEGER NOT NULL,
      edited_by TEXT, edited_at TEXT,
      notification_sent_at TEXT, delivered_at TEXT,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
      UNIQUE(senior_id, period_start));

jobs(id INTEGER PRIMARY KEY AUTOINCREMENT,
      job_type TEXT NOT NULL,               -- weekly_digest | notify_digest | retention_purge
      payload_json TEXT NOT NULL DEFAULT '{}',
      due_at TEXT NOT NULL,
      status TEXT NOT NULL CHECK(status IN ('pending','running','done','failed','dead')),
      attempts INTEGER NOT NULL DEFAULT 0, max_attempts INTEGER NOT NULL DEFAULT 5,
      lease_expires_at TEXT,
      idempotency_key TEXT NOT NULL UNIQUE,
      last_error TEXT,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL);

schedule_proposals(id INTEGER PRIMARY KEY AUTOINCREMENT,
      senior_id INTEGER NOT NULL REFERENCES users(id),
      caregiver_id INTEGER NOT NULL REFERENCES users(id),
      payload_json TEXT NOT NULL,           -- subset of preferences fields
      status TEXT NOT NULL CHECK(status IN ('pending','approved','rejected','cancelled')),
      created_at TEXT NOT NULL, decided_at TEXT);

contact_actions(id INTEGER PRIMARY KEY AUTOINCREMENT,
      senior_id INTEGER NOT NULL REFERENCES users(id),
      actor_user_id INTEGER NOT NULL REFERENCES users(id),
      contact_id INTEGER NOT NULL REFERENCES contacts(id),
      phone TEXT NOT NULL,
      initiated_at TEXT NOT NULL,
      confirmed_at TEXT);                   -- user confirms the call actually happened

checkin_events(id INTEGER PRIMARY KEY AUTOINCREMENT,
      senior_id INTEGER NOT NULL REFERENCES users(id),
      device_id TEXT NOT NULL,
      local_date TEXT NOT NULL,
      outcome TEXT NOT NULL CHECK(outcome IN ('shown','dismissed','accepted','no_response')),
      created_at TEXT NOT NULL);

notifications(id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL REFERENCES users(id),
      kind TEXT NOT NULL,                   -- digest_ready | invitation | relationship
      title TEXT NOT NULL, body TEXT NOT NULL,  -- generic only, never health content
      read_at TEXT, created_at TEXT NOT NULL);

audit_events(id INTEGER PRIMARY KEY AUTOINCREMENT,
      actor_user_id INTEGER, action TEXT NOT NULL, target_type TEXT NOT NULL,
      target_id TEXT, outcome TEXT NOT NULL, created_at TEXT NOT NULL);
-- audit_events MUST NOT contain transcript, audio, memory text or digest item text.
```

Indexes: `relationships(senior_id)`, `observations(senior_id, event_date)`,
`digests(senior_id, period_start)`, `jobs(status, due_at)`, `notifications(user_id, read_at)`,
`checkin_events(senior_id, local_date)`, `memories(senior_id, approval_state)`.

## 4. Identity and authorization

- `POST /api/v1/dev/login` (only when `ANCHOR_ENV != production`): `{"user_id": 1}` →
  `{"access_token","token_type":"bearer","expires_in"}`. Token = base64url(payload) + "." +
  base64url(HMAC-SHA256(payload, secret)); payload `{sub, role, exp}`.
- Real deployments use an OIDC adapter (`auth.py` `IdentityProvider` protocol); no password storage
  anywhere. Seeded demo users exist only in `seed_demo.py`/test fixtures.
- Every endpoint except `/health` and `/dev/login` requires a valid bearer token (401 otherwise).
- `require_senior()`: token role `senior`, and the resource `senior_id` must equal `sub`.
- `require_caregiver()`: token role `caregiver`.
- Caregiver access to a senior requires `relationships.status='accepted'` (revoked/pending → 403
  `relationship_inactive`). Never trust a client-supplied owner id.
- Caregiver may only ever read: `/me`, relationship status, own notifications, approved+permitted
  digest content, and the senior's saved contact for the digest call action. Conversations, turns,
  memories, raw observations, preferences details, and private digests → 403
  `caregiver_scope_denied`.
- Audit every consent change, revocation, approval, deletion, call initiation, digest delivery.

## 5. Consent engine (shared enforcement service)

Capabilities: `cloud_processing`, `proactive_invitations`, `save_memory`,
`record_observations`, `share_topic:<topic>` with topics
`participation | activities | mood | meals | wellbeing`.

Rules:
1. A missing row means **not allowed** (private-by-default). Seed explicit rows.
2. `consent_state.version` increments on every changed consent. Each consent row stores the version
   at which it was set.
3. Enforcement happens **before retrieval/transmission**, not before rendering:
   - session open/turn → `cloud_processing`
   - proposing/approving a memory → `save_memory`
   - writing an observation → `record_observations` + topic permitted by user's chosen topics
     (record_observations is one switch; topics default to all five once enabled, but a topic can be
     excluded by `share_topic:<topic>` being explicitly false? — no: `share_topic` only governs
     sharing. Recording uses `record_observations`; the senior chooses which topics to record via
     PATCH `/preferences` `observation_topics` — see §6.3.)
   - scheduling/attempt → `proactive_invitations`
   - digest generation → `record_observations` + `share_topic:<topic>` (draft shows only permitted topics)
   - delivery / every caregiver retrieval → re-check relationship + `share_topic:<topic>` + current
     `consent_version`; drop items whose topic is no longer permitted.
4. `PUT /consents` is version-checked (`base_version`) → 409 `consent_version_conflict` on mismatch.
5. Revocation of a relationship immediately: marks pending/awaiting digests `cancelled`, deletes
   pending `notify_digest` jobs, and blocks caregiver reads (`403 relationship_inactive`).

## 6. API contract

Base `/api/v1`. JSON. Errors: `{"error": {"code": "...", "message": "..."}}`.
Codes: `unauthorized`, `forbidden`, `caregiver_scope_denied`, `relationship_inactive`,
`consent_required`, `consent_version_conflict`, `not_found`, `validation_error`, `conflict`,
`daily_cap_reached`, `outside_greeting_window`, `quiet_hours`, `session_stopped`,
`provider_unavailable`, `insufficient_information`.

### 6.1 Identity / setup
| Method | Path | Auth | Contract |
|---|---|---|---|
| GET | `/me` | any | `{id, role, display_name, timezone, locale, senior_id, relationship_status}`; caregiver `senior_id` = linked senior or null |
| POST | `/dev/login` | none | dev only → token |
| POST | `/invitations` | senior | `{expires_in_hours?=24}` → `{id, token, expires_at, accept_path}`; token returned once |
| POST | `/invitations/accept` | caregiver | `{token}` → `{relationship_id, status:"pending"}`; invalid/used/expired → 410 `invitation_invalid`; does NOT grant sharing |
| GET | `/relationships` | any | senior: caregivers linked; caregiver: own links |
| POST | `/relationships/{id}/approve` | senior | pending → accepted; 404 own-only; notifies caregiver generically |
| DELETE | `/relationships/{id}` | senior | revoke; cancels unsent digests; 403 for non-owner; idempotent |
| GET/PUT | `/consents` | senior | GET: `{version, items:[{capability,topic,allowed,version,updated_at}]}`. PUT `{base_version, changes:[{capability, topic?, allowed}]}` → new version; 409 on mismatch; validation: `share_topic` requires known topic; capabilities without topic must have empty topic |
| GET/PATCH | `/preferences` | senior | PATCH accepts greeting window (`HH:MM`), quiet hours, `daily_cap` ∈{0,1}, `paused`, `snoozed_until`, `voice_pace`, `short_replies`, `language`, `interests[]`, `designated_device_id`, `observation_topics[]`, `digest_retention_days`; validates `HH:MM`, window ≠ crossing semantics allowed; returns full state |
| POST | `/schedule-proposals` | caregiver | `{payload}` restricted to greeting window / daily_cap / pause; → pending; must be linked accepted |
| GET | `/schedule-proposals` | any | senior: own incoming; caregiver: own proposals |
| POST | `/schedule-proposals/{id}/approve` | senior | applies payload to preferences atomically → approved; only pending |

### 6.2 Proactive check-ins (S1/S7 evidence; extension endpoints)
| Method | Path | Auth | Contract |
|---|---|---|---|
| GET | `/checkins/eligibility` | senior | `?device_id=` → `{eligible, reasons[], window:{start,end}, quiet_hours:{start,end}, cap_remaining, local_time, local_date, designated_device_ok}` |
| POST | `/checkins/attempts` | senior | `{device_id, outcome}` → records attempt; **409 `daily_cap_reached`** if today's attempts ≥ cap; **409 `outside_greeting_window`** if now outside; **409 `quiet_hours`** if inside; 409 `not_designated_device` if device mismatch; 409 `consent_required` if proactive consent off |
| GET | `/checkins/schedule` | senior | computed local notification schedule for next 7 days: `{entries:[{date, local_time, title, body}], note}`; empty when paused/snoozed/cap 0/consent off |

Eligibility rules (all must hold): proactive consent; designated device; local time in greeting
window; outside quiet hours (window may cross midnight); not paused; not snoozed; attempts today <
cap; no active session. Attempts are recorded regardless of response. Dismissed/no_response must not
be retried the same day.

### 6.3 Conversation (S2/S4/S6/S7/S9)
| Method | Path | Auth | Contract |
|---|---|---|---|
| POST | `/sessions` | senior | `{origin, device_id?}`; requires `cloud_processing` else 403 `consent_required`; if active session exists → 409 `conflict` with `session_id`; → `{session_id, state:"active", mic_on:true, started_at, greeting_text?}` (greeting only when local time in greeting window and origin=proactive) |
| GET | `/sessions/{id}` | senior owner | `{session_id,state,started_at,ended_at,captions:[{role,text,at}],mic_on}`; caregiver → 403 |
| POST | `/sessions/{id}/turns` | senior owner | body `{text}` **or** `{audio_b64, audio_mime}`; response `{turn_id, transcript, reply_text, intent, action?, captions, stopped:false}`; 409 `session_stopped` after stop; 403 `consent_required` if cloud consent revoked mid-session; audio is never persisted |
| POST | `/sessions/{id}/stop` | senior owner | idempotent → `{state:"stopped"}`; purges turn text; background/late generations discarded (cancellation token) |

Turn pipeline (order matters):
1. reject if session not active (409 `session_stopped`).
2. re-check cloud consent (403) and cancellation token.
3. transcribe audio via ASR adapter if `audio_b64`; echo transcript; on provider failure →
   `503 provider_unavailable` with `recovery:["retry","type_instead"]`.
4. deterministic command routing (before LLM): `stop` (停/停止/别说了/先别说了/stop/quiet),
   `repeat` (再说一遍/重复/repeat), `play` (玩/游戏/下棋/play), `call` (打电话/给…打电话/call/call [name]).
   - stop → mark session stopped, purge turns, return `stopped:true` and `action:{type:"stop"}`.
   - repeat → re-send last anchor reply, no LLM call.
   - play → `action:{type:"activity", activity_id}` selecting next rotation item.
   - call → resolve contact by label/name; if unresolved ask one clarification
     (`ask:{kind:"clarify", options:[contact labels]}`); if resolved return
     `action:{type:"dial", contact_id, label, phone, requires_confirmation:true}` and create a
     pending `contact_actions` row. Confirmation is required before dialing.
5. otherwise generate reply via LLM adapter using: approved memories only, last 6 turns, language,
   short-reply flag, pace hint; ask at most one question; never diagnose/score; a diagnostic reply
   is replaced by a safe template (test).
6. write turns, record observations when `record_observations` is allowed (topic inferred from
   deterministic keywords: meal/饭/吃, mood/心情/高兴/累, activity/玩/游戏/下棋, participation fallback;
   evidence is the senior's own words, truncated to 140 chars).
7. return captions list for the session.

Cancellation: `POST /stop` sets the token state; the orchestrator checks `is_cancelled()` before
writing/model-callback and discards late output (test injects a slow fake LLM).

### 6.4 Memory (S2)
| Method | Path | Auth | Contract |
|---|---|---|---|
| GET | `/memories` | senior | `{items:[{id, fact, approval_state, approved_at, created_at}]}`; deleted excluded |
| POST | `/memories` | senior | `{fact, source_ref?}` → proposed fact; 403 `consent_required` if `save_memory` off; `fact` 3–200 chars |
| POST | `/memories/{id}/approve` | senior | proposed → approved with `approved_at` |
| DELETE | `/memories/{id}` | senior | hard delete + audit; excluded from all retrieval immediately |

Retrieval: approved memories, topic/keyword overlap with current utterance or interests, recency;
limit 5. A test freezes time, approves a fact, advances 7 days, converses, and asserts the reply
contains the fact (`memory_recall_7d`).

### 6.5 Activities (S3)
| Method | Path | Auth | Contract |
|---|---|---|---|
| GET | `/activities` | senior | `{items:[{id,type,title,prompt,options?,answer?,minutes}], rotation:[ids]}`; `type` ∈ trivia/story/memory; filtered by interests when possible |
| POST | `/activity-sessions` | senior | `{activity_id, completed, duration_seconds}` → records observation topic `activities` when `record_observations` allowed; deterministic next-rotation state persisted (`activity_rotation` table? see DECISIONS — store in preferences JSON `rotation_state` — no: separate `rotation_state` table is allowed, add it) |

Deterministic rotation: never repeat an item until all items of that type (or interest group) have
been shown; persisted so it survives restart. Session default 3 minutes, early stop allowed.

### 6.6 Digest + family bridge (S10/S11)
| Method | Path | Auth | Contract |
|---|---|---|---|
| GET | `/digests` | senior/caregiver | senior: own, all states (preview). caregiver: only `approved`/`delivered` for linked senior, items filtered by current `share_topic` consents + relationship accepted; if none → `{items:[], note:"insufficient_information"}` |
| GET | `/digests/{id}` | senior/caregiver | same filtering; 403 `caregiver_scope_denied` if not linked/approved |
| PATCH | `/digests/{id}` | senior | `{items}` max 3, each `{topic,text,evidence_ids[]}`; any edit → status `awaiting_senior_approval`, clears `edited_by` approval; text passes language guard |
| POST | `/digests/{id}/approve` | senior | only `awaiting_senior_approval` → `approved`, snapshot `consent_version`, enqueue `notify_digest` job (idempotent key `notify_digest:{digest_id}`) |
| POST | `/contact-actions` | senior/caregiver | `{contact_id, confirmed?}`; senior: own contact; caregiver: must be linked+accepted, and the contact must belong to the senior; → `{contact_action_id, label, phone, dial_uri:"tel:+..."}`; records initiation; caregiver call action allowed only for the digest's senior |
| GET | `/notifications` | any | own generic notifications; `PATCH /notifications/{id}` mark read (optional) |

Digest lifecycle: `draft → awaiting_senior_approval → approved → delivered`; edit resets approval;
unapproved/undelivered → `cancelled` on revocation or deletion.

`GET /digests` senior preview includes `insufficient_data` message when the week lacks evidence:
`{"status":"insufficient_data","message":"这周的信息还不够，先不下结论。","items":[]}` — never pad to 3.

### 6.7 Data rights (S8/S9)
| Method | Path | Auth | Contract |
|---|---|---|---|
| DELETE | `/data` | senior (body `{confirm:true}`) | deletes memories, observations, turns/sessions, digests, contact actions, check-in events; cancels jobs; revokes relationships; bumps consent version; stores no content in audit; → `{deleted:{table:count}}` |

### 6.8 Health
`GET /health` → `{status:"ok", version, time, offline_capabilities:["stop","settings","cached_activities","system_calling"]}`

## 7. Digest content rules (S10 + §8)

Generation (worker `weekly_digest`, due each Monday 09:00 local for the previous 7 days):
1. period = previous ISO week in senior's local timezone (Monday..Sunday).
2. Adequate data: distinct observed days in current period ≥ 3 and in the prior 14 days ≥ 6.
   Else create `insufficient_data` digest with the honest message (still one row, still idempotent).
3. Consider only observations whose topic is currently `share_topic` permitted.
4. Select ≤ 3 items, ordered by relevance: topic changed vs baseline first, then frequency.
   Baseline = per-day rates over the previous 14 days; a change is |current_rate - baseline_rate|
   ≥ 0.5/day or a topic appears that had no prior evidence.
5. Render deterministic plain-language text (locale-aware templates) with `evidence_ids` pointing to
   observation ids. No model rewriting in MVP.
6. Language guard: reject/rewrite any item containing diagnostic or scoring language. Banned
   patterns: 诊断, 痴呆, 认知, 抑郁, 评分, 分数, 健康分, 预警, 退化, dementia, diagnosis, cognitive,
   depression, score, risk level. An item failing the guard must never reach `items_json` (generator
   falls back to a safe template; edit endpoint returns 422 `validation_error`).
7. Every item has ≥1 evidence reference; no filled slot may be unsupported. Three is a maximum, not
   a quota.

Delivery: `notify_digest` sends a generic notification (“本周家庭简报已就绪” / “Weekly update ready”)
with no details; caregiver opens authenticated digest. Every caregiver read re-filters items.

Retention: observations older than 35 days purged daily; digests kept `digest_retention_days`
(default 365) then purged; audit events kept 180 days; notification rows purged with digests.
Deletion request removes everything immediately.

## 8. Worker

`python -m app.worker --once` and continuous mode.
- Job claim: `BEGIN IMMEDIATE`; select `status IN ('pending','failed') AND due_at<=now AND
  (lease_expires_at IS NULL OR lease_expires_at<now)`, set `running`, `attempts+1`,
  `lease_expires_at=now+lease`; commit; execute; success → `done`; error → `failed` with backoff
  (2^attempts minutes), attempt ≥ max_attempts → `dead`.
- `weekly_digest` idempotency key `weekly_digest:{senior_id}:{period_start}`; digest row unique
  (senior_id, period_start). Running twice must not duplicate.
- `notify_digest` keyed by digest id; only sends if digest still `approved` and relationship active,
  re-checking consents; then sets `delivered` + `delivery` notification.
- `retention_purge` daily; safe when run repeatedly.
- Worker restart mid-job: lease expiry allows reclaim exactly once (test with fake failing job).

## 9. Flutter application contract

- **Senior mode:** Home (three large buttons Talk / Play / Call + Settings), Talk screen
  (mic indicator, captions, Repeat, Stop), Play (trivia/story/memory game, three minutes),
  Call (saved contacts, confirmation, system dialer), Settings (greeting window, quiet hours, pause,
  voice pace, short replies, language, approved memories list with delete, sharing topics, digest
  preview/approve, revoke access, delete my data).
- **Caregiver mode:** invitation acceptance, weekly digest (≤3 highlights + Call to check in),
  preferences (propose schedule), connection/consent status. No monitoring feed, no conversation
  history, no location, no health scores.
- **Stop/Not now** is visible on every screen. Local cancellation must work instantly even while a
  network request is in flight (UI switches immediately; late response ignored by request nonce).
- **Accessibility:** main text 26 logical px, primary targets ≥56 px, high contrast, labels + icons,
  Semantics labels for screen readers, respects text scaling, `MediaQuery` layouts for phone
  (<600) and tablet (≥600).
- **Runtime:** mic capture via `record`; playback via `flutter_tts` (device voice);
  text input fallback always available; dialing via `url_launcher` `tel:` with visible number
  fallback; credential stored in memory per run (Windows/mobile secure storage is a documented
  limitation and a TODO adapter).
- **Offline:** Stop, settings, cached activities, calling remain usable; Talk explains that online
  conversation is unavailable with Retry/Type options. `InvitationScheduler` is pure Dart and
  unit-tested (window, quiet hours crossing midnight, cap, snooze, timezone/DST, restart).

## 10. Test & acceptance matrix (pytest + flutter test IDs)

Required failure tests (§8) — all must exist:
- `failure_revoke_after_draft` — revoke a topic after draft → blocked at delivery and retrieval.
- `failure_cross_household` — caregiver cannot read another household's digest or change consent.
- `failure_delete_memory` — deleted memory absent from prompts and derived drafts.
- `failure_stop_late_output` — stop during slow generation prevents late output from resuming.
- `failure_quiet_hours_midnight` — quiet hours crossing midnight + timezone change add no invitations.
- `failure_worker_restart` — restart does not duplicate weekly digest/notification.
- `failure_sparse_data` — sparse data produces the honest insufficient-information message.
- `failure_offline` — no internet: Stop and system calling still work; recovery options shown.

Authorization/consent suite (S8/S9): `authz_*` ≥ 15 cases incl. client-supplied ids, revoked
relationship, private topics, caregiver scopes, invitation reuse/expiry, consent version conflicts.

Surface tests: `s1_` check-ins; `s2_` dialogue/memory 7d; `s3_` activities rotation; `s4_` one-step
commands; `s5_` layout (Flutter widget tests, phone/tablet); `s6_` recovery/captions; `s7_` stop;
`s9_` no camera (scan manifests) + mic indicator; `s10_` digest; `s11_` contact; `s12_` setup.

Acceptance measures harness: `tests/test_acceptance_matrix.py` maps every §8 row to a test id and a
machine check where possible; user-study-only rows are marked `MANUAL` and must appear in
`docs/acceptance-checklist.md` as "not yet measured" (never "achieved").

Speech metrics: `scripts/eval_wer.py` computes WER = (S+D+I)/N against a reference JSON; supports
Mandarin whitespace-free tokenization via `--tokenizer char`; reports dialect groups separately.

## 11. Definition of done

`scripts/verify.ps1` exits 0 and performs:
1. `pytest -q backend/tests` (all pass, includes the required failure tests + acceptance matrix)
2. `dart format --output=none --set-exit-if-changed lib test` (or `flutter analyze` clean)
3. `flutter analyze` with zero errors
4. `flutter test` all pass
5. `flutter build windows --debug` succeeds from the ASCII build dir (script handles CMake 4.x,
   nuget, and the non-ASCII path).
6. `python scripts/seed_demo.py --check` + `python -m app.worker --once` smoke against a temp DB.
7. `docs/acceptance-checklist.md` has every box linked to evidence (test id / command / file) or
   marked `MANUAL - not measured`.
