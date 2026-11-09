# Anchor MVP — setup and operations

This document is the operator guide required by the MVP definition: provider configuration, database
handling, worker recovery, retention/deletion procedures, and device setup. See `../SPEC.md` for the
contract and `../Anchor_Software_Design_and_MVP_Guide.md` for product intent.

## 1. Prerequisites (this machine)

| Component | Version used | Notes |
|---|---|---|
| Windows | 11 24H2 (10.0.26100) | demo form is a Windows desktop build |
| Python | 3.10 | `.venv` under `anchor/.venv` |
| Flutter | 3.47.2 stable (Dart 3.13.2) | Windows desktop + Android + web enabled |
| Visual Studio | 2026 Community, Desktop C++ workload | for the Windows runner |
| nuget.exe | downloaded by `scripts/build_windows.ps1` | `flutter_tts` Windows build dependency |

The workspace path contains non-ASCII characters (`Ⅱ 26 Fall`). CMake 4.x and the Dart analysis
server both fail there, so **every Flutter command runs against an ASCII mirror** created by
`scripts/_common.ps1:Sync-MobileToAscii` (`%LOCALAPPDATA%\anchor-build\mobile`). Never run
`flutter build windows` directly in the vault path.

## 2. First run

```powershell
cd anchor
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/bootstrap.ps1   # venv + deps + DB
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify.ps1     # gate
```

Terminal A — backend (`http://127.0.0.1:8077`):

```powershell
powershell -File scripts/run_backend.ps1
```

Terminal B — worker (weekly digests, retention):

```powershell
powershell -File scripts/run_worker.ps1
```

Terminal C — desktop app:

```powershell
powershell -File scripts/run_app.ps1        # builds first if needed; add -Rebuild to force
```

Demo data: `python scripts/seed_demo.py` (from `anchor/backend`, using the venv). It creates senior
user 1 (`林秀兰`) and caregiver user 2 (`Mei`) with an accepted link, consents, contacts, a week of
observations, one approved memory, and activity history. Log in with the user ids on the app's demo
screen (`POST /api/v1/dev/login`).

## 3. Environment variables (`ANCHOR_*`)

| Variable | Default | Purpose |
|---|---|---|
| `ANCHOR_ENV` | `dev` | `dev` / `test` / `production`; production rejects the default secret and requires provider URLs |
| `ANCHOR_SECRET` | dev constant | HMAC key for bearer tokens; **must** change in production |
| `ANCHOR_DB_PATH` | `backend/data/anchor.db` | SQLite file |
| `ANCHOR_TIMEZONE` | `Asia/Shanghai` | default account timezone (per-user timezone wins) |
| `ANCHOR_TOKEN_TTL_SECONDS` | `86400` | bearer token lifetime |
| `ANCHOR_WORKER_INTERVAL_SECONDS` | `60` | worker poll interval |
| `ANCHOR_JOB_LEASE_SECONDS` | `120` | job lease; expired leases are reclaimed |
| `ANCHOR_ASR_PROVIDER` | `fake` | `fake` (tests/offline) or `http` (OpenAI-compatible `/audio/transcriptions`) |
| `ANCHOR_ASR_URL` / `ANCHOR_ASR_API_KEY` / `ANCHOR_ASR_MODEL` | — / — / `whisper-1` | ASR endpoint |
| `ANCHOR_LLM_PROVIDER` | `rule` | `rule` (deterministic, offline) or `http` (OpenAI-compatible `/chat/completions`) |
| `ANCHOR_LLM_URL` / `ANCHOR_LLM_API_KEY` / `ANCHOR_LLM_MODEL` | — / — / `deepseek-chat` | conversation model |

The `fake`/`rule` defaults keep the demo and the whole test suite network-free. Switching to hosted
providers is configuration only (`app/providers/__init__.py:build_providers`).

**Speech data note:** with the `http` ASR provider, audio leaves the device. The consent screen must
say “声音会经过网络” before enabling cloud processing; the backend never persists raw audio.

### 3.1 Connecting a real model and real speech (required for a convincing demo)

The offline defaults are deliberate: `rule` is a deterministic template engine and ASR is `none`
unless a provider or the local Windows recognizer is available. The app ships **Settings → AI 接入**
for the older adult (or the demo operator):

1. **LLM** — paste a DeepSeek (or any OpenAI-compatible) base URL + model + API key. The
   **填入 DeepSeek 预设** button fills `https://api.deepseek.com` / `deepseek-chat`. Save then
   **测试连接**; a reply sample proves the key works. Replies become real immediately (no restart).
2. **ASR** — on Windows the effective engine is `windows-sapi` (offline System.Speech, zh-CN when
   installed): real recognition, no key. Alternatively configure an OpenAI-compatible
   `/audio/transcriptions` endpoint. If neither exists, the Talk mic is disabled with an honest
   “语音识别还没有接入” message and typing stays available.
3. Keys are stored in the local SQLite file in plaintext for this self-hosted demo (documented
   limitation; never ship the DB). They are masked in every API response and never logged.

Equivalent environment configuration (takes effect on start; a stored row wins over env):

```powershell
$env:ANCHOR_LLM_PROVIDER = "http"
$env:ANCHOR_LLM_URL = "https://api.deepseek.com"
$env:ANCHOR_LLM_API_KEY = "sk-..."
$env:ANCHOR_LLM_MODEL = "deepseek-chat"
$env:ANCHOR_ASR_PROVIDER = "auto"   # windows-sapi on this machine; or http + URL/KEY/MODEL; or none
```

The packaged demo exe sets `ANCHOR_ASR_PROVIDER=auto` itself. `GET /api/v1/providers` reports the
effective engine; `PUT /api/v1/providers` and `POST /api/v1/providers/test` are the runtime API
(SPEC §6.9).

## 4. Database

- SQLite file at `ANCHOR_DB_PATH`; WAL mode; one process-wide connection with serialized writes.
- Schema is versioned by `backend/migrations/*.sql` and applied at startup (`schema_migrations`).
  Add a new numbered file for every schema change; never edit an applied migration.
- Single-server pilot assumption: keep the DB on local persistent disk, back up by copying the file
  while the backend is stopped (or use SQLite's online backup API in a script), and keep the worker
  on the same host. Move to a server database before adding concurrency or a second host.
- Demo reset: stop backend, delete `backend/data/anchor.db*`, start again, re-run the seed.

## 5. Worker and job recovery

- Jobs live in the `jobs` table. Claiming is `BEGIN IMMEDIATE` + `status='running'` +
  `lease_expires_at=now+ANCHOR_JOB_LEASE_SECONDS`; attempts increment on claim.
- A crashed worker leaves an expired lease; the next run reclaims the job. Attempts past
  `max_attempts` move the job to `dead` (visible for inspection, never retried silently).
- `notify_digest` and `weekly_digest` are idempotent: the job's `idempotency_key` is unique and the
  digest row is unique on `(senior_id, period_start)`, so a restart cannot publish duplicates.
- Run once for tests/ops: `python -m app.worker --once`.
- Inspect: `SELECT id, job_type, status, attempts, lease_expires_at, last_error FROM jobs;`
- Requeue a dead job: set `status='pending', attempts=0, due_at=<now>`; do **not** delete the row
  (the idempotency key protects against duplicates).

## 6. Retention and deletion procedures

| Data | Default retention | Mechanism |
|---|---|---|
| Raw audio | 0 — never written to disk; transcribed in memory only | orchestrator discards the buffer |
| Turn text | active session only | `POST /sessions/{id}/stop` / session end purges `turns` |
| Observations | 35 days | worker `retention_purge` |
| Approved memories | until the older adult deletes them | `DELETE /memories/{id}` |
| Digests | `preferences.digest_retention_days` (default 365) | worker `retention_purge` |
| Audit events | 180 days, content-free | worker `retention_purge` |

Deletion request: `DELETE /api/v1/data` with `{"confirm": true}` (senior token). It deletes memories,
observations, sessions/turns, digests, contact actions and check-in events, cancels jobs, revokes the
caregiver relationship, bumps the consent version, and writes a content-free audit row. It cannot
recall information a caregiver already viewed or copied — say this plainly during onboarding.

Revocation: `DELETE /relationships/{id}`. It cancels unsent digests, drops pending `notify_digest`
jobs, cancels pending schedule proposals, and every subsequent caregiver read returns 403.

Provider-side retention is outside our control: configure the hosted ASR/LLM account consistently and
do not promise immediate deletion of provider copies unless the vendor supports it.

## 7. Device setup

**Windows demo (target artefact):** run `scripts/run_app.ps1`; the app talks to
`http://127.0.0.1:8077`. Microphone permission is requested by the OS on first capture; if the
plugin or permission is unavailable the Talk screen keeps the text fallback. Stop is local and works
even while a request is in flight.

**Android target (not verified on a physical device in this build):** `flutter build apk --debug`
from the ASCII mirror. Do not add camera permissions; the manifest must stay camera-free (a test
asserts this). Notification permission is required for background invitations; if denied, the app
must explain that background invitations are unavailable and keep foreground greetings.

**Designated invitation device:** set `preferences.designated_device_id` to one device id. Other
devices report `designated_device_mismatch` and never schedule invitations. Changing the designated
device requires the older adult (PATCH /preferences); a caregiver can only propose it and the senior
must approve.

## 8. Operating checklist before a pilot

1. `scripts/verify.ps1` green (backend tests, analyze, tests, Windows build, seed check).
2. `ANCHOR_ENV=production` + real `ANCHOR_SECRET`; provider URLs and keys set; audio-egress notice
   added to the consent copy.
3. Backups configured; single worker instance; job dashboard query bookmarked.
4. Retention values confirmed with the older adult during onboarding (`digest_retention_days`).
5. Pilot measurement kit printed: `docs/measurement.md` + the consent form in
   `../04 老人测试与同意书.md`.
6. Every §9 acceptance item in `docs/acceptance-checklist.md` either has evidence or is marked
   `MANUAL – not measured`.
