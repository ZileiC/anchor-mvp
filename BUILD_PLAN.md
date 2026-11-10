# BUILD_PLAN — Anchor MVP execution ledger

**This file is the durable memory of the build loop.** A fresh agent with no conversation history
must be able to open the workspace, read this file, and continue correctly.

## 0. How to work a round (mandatory)

1. Read `SPEC.md` (contracts), this file, and `DECISIONS.md` (append-only). Skim `../Anchor_Software_Design_and_MVP_Guide.md`
   only when a product question is not answered by `SPEC.md`.
2. Run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify.ps1 -BackendOnly` to see
   the current baseline. It must be green before you start; if it is not, fixing it is your first task.
3. Pick the **first milestone whose status is not DONE**. Work its next unchecked item to completion.
   Keep the repository green at every step; never leave a broken import or a failing test behind.
4. Write tests **before or with** the behavior. Never weaken or delete a test to make it pass.
   If a contract is genuinely wrong, append a decision to `DECISIONS.md`, update `SPEC.md`, and note
   it in the progress log.
5. At the end of the round run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify.ps1`
   (full; use `-SkipBuild` only when the Windows build is unaffected by your change).
6. Update the milestone checkboxes and append one line to the progress log:
   `YYYY-MM-DDTHH:MM | Mx | what changed | tests added/changed | verify result`.
7. Mark a milestone `DONE` only when every checkbox in it is checked **and** its evidence command is
   green. Otherwise leave it `IN PROGRESS` with the next unchecked item stated explicitly.

**Rules**

- One repository, one truth: no duplicate implementations, no commented-out dead code.
- No writes outside `anchor/` (this folder).
- No secrets in git; no network calls in tests; no sleeps > 1 s in tests (use the injected clock).
- Provider calls are always behind adapters with fakes for tests.
- UI text is bilingual: zh-CN default, English when `locale` is `en`. No health/diagnostic wording.
- Security: every new endpoint gets at least one authorization test; every consent change gets an audit row.
- Formatting: `ruff`-style discipline without the tool (4 spaces, 100 cols). Flutter uses `dart format`.
- **Do not stop before `scripts/verify.ps1` is fully green and every milestone below is DONE.**

## 1. Milestones

### M0 — Foundation (status: DONE)
- [x] `backend/requirements.txt`, `pytest.ini`, package skeleton exactly as in SPEC §1
- [x] `app/config.py` (Settings, env), `app/clock.py` (Clock/FakeClock), `app/errors.py`
- [x] `app/db.py`: connect/migrate/transaction/row helpers; `migrations/001_init.sql` = SPEC §3 + rotation/observation-topic storage decided in DECISIONS
- [x] `app/main.py` `create_app()` with error handler, `/health`, dev-login token issuing/verification
- [x] pytest fixtures: temp DB, app factory, fake clock, senior/caregiver tokens (5+ tests green)
- [x] `scripts/bootstrap.ps1`, `run_backend.ps1`, `run_worker.ps1`, `verify.ps1` (full skeleton)
- [x] `.gitignore`, `DECISIONS.md`, `README.md` skeleton
- **Evidence:** `pytest -q` green (health + auth + migration tests); `scripts/verify.ps1 -BackendOnly` green.

### M1 — Identity, consent, preferences, check-ins (status: DONE)
- [x] `/me`, invitations (single-use, hashed, expiry), accept, approve, list, revoke
- [x] Consent engine + `GET/PUT /consents` (versioning, 409 on conflict, audit)
- [x] Preferences read/patch with validation; observation topics; designated device
- [x] Schedule proposals (caregiver → senior approval applies atomically)
- [x] Check-in eligibility/attempts/schedule with daily cap, window, quiet hours crossing midnight,
  pause/snooze, designated device, no-active-session
- [x] `authz_*` suite ≥15 cases incl. cross-household and client-supplied-id attacks; `s12_` setup test
- **Evidence:** backend suite green; every S1/S7/S12 API rule has a test id.

### M2 — Conversation, memory, activities (status: DONE)
- [x] Provider protocols + fakes + `llm_rule` deterministic dialogue + `asr_http`/`llm_http` adapters
- [x] Command routing (stop/repeat/play/call) with one clarification, confirmation-required dial action
- [x] Session open/turns/stop, captions, cancellation token, no audio persistence, turn purge
- [x] Memory propose/approve/list/delete/retrieval; 7-day recall test; prompt excludes deleted facts
- [x] Activity content pack (`content/activities.json`, 3 types, 16 adult-level items with explanations and spoken feedback), rotation persisted, activity sessions + observations
- [x] Tests: `s2_`, `s3_`, `s4_`, `s6_`, `s7_`, `failure_stop_late_output`, `failure_delete_memory`
- **Evidence:** backend suite green including cancellation and 7-day recall.

### M3 — Family bridge, worker, retention (status: DONE)
- [x] Digest generation (adequate-data rule, ≤3 supported items, evidence refs, deterministic render)
- [x] Language guard (banned diagnostic patterns) on generation + edit
- [x] Draft/edit/approve/deliver lifecycle; caregiver filtering by current consent; generic notification
- [x] Worker: claim with lease, attempts/backoff/dead, `--once`, weekly idempotency, notify idempotency, retention purge
- [x] Contact actions (senior + caregiver), saved contacts, dial URI recording
- [x] Revocation/deletion semantics (cancel drafts, delete derived data, bump consent version)
- [x] Tests: `failure_revoke_after_draft`, `failure_cross_household`, `failure_worker_restart`,
  `failure_sparse_data`, `s10_`, `s11_`, retention/deletion tests
- **Evidence:** `backend/tests/test_digests.py` (25), `test_worker.py` (9), `test_contacts.py` (14),
  `test_data_rights.py` (10); 283 tests green; worker run twice leaves one digest / one notification.

### M4 — Backend acceptance harness & docs draft (status: DONE)
- [x] `tests/test_acceptance_matrix.py` mapping every §8 row to a test id; MANUAL rows explicit
- [x] `scripts/eval_wer.py` (S+D+I)/N with char tokenizer + dialect groups
- [x] `tests/test_no_camera_capability.py` scanning mobile manifests for camera/microphone policy
- [x] `scripts/seed_demo.py` idempotent demo data (senior 1 + caregiver 2, consents, contacts, week of observations, one memory, one activity history)
- [x] `docs/measurement.md` protocol for the MANUAL rows (WER, unaided completion, memory, digest rating, family contact)
- **Evidence:** `pytest -q` = 283 passed; `scripts/verify.ps1 -BackendOnly` exit 0; `seed_demo --check` OK.

### M5 — Flutter shell, core screens, state (status: DONE)
- [x] `theme.dart` (26 px text, 56 px targets, contrast), `app.dart`, routing by role
- [x] API client + credential store + models; app state (session, consent snapshot, settings)
- [x] Home (Talk/Play/Call/Settings, Stop bar), Talk (text mode, captions, mic indicator, Repeat/Stop), Settings basics
- [x] Widget tests: home layout phone/tablet, one-tap reachability, stop visible everywhere, text sizes
- [x] `flutter analyze` zero errors; `dart format` clean
- **Evidence:** `flutter analyze` No issues; `flutter test` 80/80 pass (home_widget 11 covers phone 390x844 + tablet 800x1200 at 1.0/1.3x).

### M6 — Flutter full feature set (status: DONE)
- [x] Play (3 activity types + rotation fetch), Call (contacts, confirmation, dialer), TTS playback, mic capture with text fallback
- [x] Settings full: greeting window, quiet hours, pause, pace, short replies, language, memories (approve/delete), sharing topics, digest preview/approve, revoke, delete data
- [x] Caregiver mode: invitation acceptance, digest, call to check in, propose schedule, connection status
- [x] InvitationScheduler (pure Dart) + unit tests (window, midnight quiet hours, cap, snooze, timezone, restart)
- [x] Offline recovery UI (Stop/settings/cached activities/call still work), request nonce discards late responses
- **Evidence:** 10 screens wired through AppState/ApiClient; 80 tests; live contract smoke against uvicorn passed for all demo endpoints.
- **Known gap carried into M7/M8:** no OS-level scheduled notification plugin — the app shows the next invitation and the foreground greeting path works, background firing is a documented limitation.

### M7 — Native build & integration (status: DONE)
- [x] `scripts/build_windows.ps1` syncs to ASCII path, applies CMake install-prefix fix, builds, copies exe + data to `mobile/dist/windows/`
- [x] `scripts/run_app.ps1` runs the built app against a local backend
- [x] App↔backend smoke: login, talk, play, stop, digest preview (recorded script or integration test)
- [x] Screenshots to `docs/img/` (10 images: login, invitation card, accepted greeting, home, talk, play, call, settings, settings topics, caregiver home/digest)
- **Evidence:** `flutter build windows --debug` green; app launched, accepted a proactive invitation and stayed alive; live flow against uvicorn verified (dev login → session → greeting → digest approval/ delivery).
- **Real bug found and fixed here:** accepting an invitation crashed the process in `flutter_tts_plugin.dll` (0xc0000005); Windows speech moved out-of-process to PowerShell `System.Speech` (`WindowsSapiSpeaker`), verified on the real exe with no post-fix crash events; Stop still kills the speech child.

### M8 — Docs, checklist, final gate (status: DONE)
- [x] `README.md` quickstart + 5-minute demo script + honest limitations pointer
- [x] `docs/setup.md` (providers, DB, worker recovery, retention/deletion, device setup)
- [x] `docs/acceptance-checklist.md` every §9 bullet + §8 row → evidence link or `MANUAL – not measured`
- [x] `docs/limitations.md` (no user study yet, speech adapter unevaluated, WER unmeasured, secure storage adapter, native path workaround)
- [x] Remove intermediate artifacts (probe scripts, temp dirs, logs); keep contract tests and verify scripts
- [x] Full `scripts/verify.ps1` green
- **Evidence:** verify exit 0 (`283` backend + `116` flutter + Windows build + seed check); `docs/acceptance-checklist.md` has no empty boxes; one-off capture/click/scroll scripts removed, screenshots kept.

## 2. Progress log (append-only, newest at bottom)

| time | milestone | change | evidence |
|---|---|---|---|
| 2026-11-05T15:45+08:00 | setup | Lead froze `SPEC.md` + `BUILD_PLAN.md`; env de-risked (Flutter 3.47.2, Windows build works via ASCII copy + nuget + CMake fix) | windows build smoke OK |

| 2026-11-05T15:52+08:00 | M0 | settings/clock/errors/db + migration 001 (SPEC §3), create_app error envelope, /health, dev-login, /me, package skeleton; bootstrap now runs the real migration | tests/test_config.py, test_db.py, test_auth.py, test_health.py (31 tests) | verify.ps1 -BackendOnly green |
| 2026-11-05T15:54+08:00 | M1 | invitations (hashed, single-use, expiry) + link lifecycle + schedule proposals; consent engine with versions/409/audit; preferences patch validation; check-in eligibility/attempts/7-day schedule; authz suite | test_relationships.py, test_consents.py, test_preferences.py, test_checkins.py (incl. failure_quiet_hours_midnight), test_authz.py (37 cases) -> 126 total | verify.ps1 -BackendOnly green |

| 2026-11-05T15:59+08:00 | M2 | providers (rule LLM, fake/HTTP ASR+LLM, notifier), command router, orchestrator (consent gate, audio->ASR, cancellation, observations), memory service (approve/delete/retrieve), 18-item activity pack with persisted rotation, sessions/memories/activities APIs | test_providers, test_s4_commands (28), test_sessions (25, incl. failure_stop_late_output), test_memories (11, incl. 7d recall + failure_delete_memory), test_activities (11) -> 216 total | verify.ps1 -BackendOnly green |
| 2026-11-05T16:07+08:00 | verify | Flutter steps (pub get/analyze/test/build) now run from the ASCII mirror via `Sync-MobileToAscii` (Dart analysis server crashes with "Unexpected end of input" on non-ASCII paths); removed the `cmtest/` CMake probe; next unchecked milestone = M3 | full `verify.ps1` green: backend 216 tests, dart format, analyze, flutter test, flutter build windows |

| 2026-11-05T16:40+08:00 | M3 | Lead re-based the foundation after a file collision, then backend-bridge shipped digests (baseline/render/language guard/service), worker + jobs (lease/backoff/dead/idempotency), retention, contacts/notifications/data endpoints, revocation+deletion semantics; DECISIONS #1–#5 logged (consent-version snapshot filtering, expired-lease recovery, GET /contacts, clock bug fix) | 283 tests green (`test_digests` 25, `test_worker` 9, `test_contacts` 14, `test_data_rights` 10); `verify.ps1 -BackendOnly` exit 0 |
| 2026-11-05T16:40+08:00 | M4 | backend-bridge shipped the §8 acceptance matrix, WER evaluator, camera-free manifest scan, idempotent demo seed, measurement protocol; manual rows stay explicitly NOT MEASURED | 283 passed; `seed_demo --check` OK; matrix asserts every mapped test id exists |
| 2026-11-05T16:47+08:00 | M5/M6 | mobile-app shipped the complete app: 10 screens (senior Home/Talk/Play/Call/Settings + caregiver home/invite/digest/propose + login), AppState/ApiClient, TTS/mic behind safe interfaces, dialer, invitation scheduler, offline recovery, accessibility theme; 80 new tests | `verify.ps1 -SkipBuild` green; analyze clean; 80/80 tests; live contract smoke OK |
| 2026-11-05T16:50+08:00 | M3 fix | Lead improved digest Chinese wording ("这周有 N 天，你说到了…") and expanded demo seed to 7 current-week days + 6 prior days so the demo digest has 3 supported items; reseeded demo DB | `test_digests` 25 pass; demo digest = 3 items with evidence ids |
| 2026-11-05T17:05+08:00 | M6 add | foreground invitation controller: Home polls eligibility, offers “现在想聊聊天吗？” with 聊一会儿 (records `accepted`, opens a proactive session, greets) / 今天不用 (records `dismissed`, no re-offer); reasons honoured verbatim; 16 controller tests + 5 widget tests | 101 flutter tests green |
| 2026-11-05T17:18+08:00 | M7 | real bug: accepting an invitation crashed the exe in `flutter_tts_plugin.dll` (0xc0000005). Windows speech replaced by out-of-process PowerShell `System.Speech` (`WindowsSapiSpeaker`), platform factory + 11 tests; live retest on the built exe stays alive and spawns a SAPI child; no post-fix crash events | 112 flutter tests green; live exe verified |
| 2026-11-05T17:24+08:00 | M6 polish | Repeat after a proactive greeting now replays the remembered greeting (server reply still wins when a turn exists); Repeat before anything said shows the existing empty copy; 4 tests | 116 flutter tests green |
| 2026-11-05T17:38+08:00 | M7/M8 | 14 live screenshots captured from the built desktop app (login, invitation, accepted greeting + Repeat, home, talk, play, call, settings ×3, caregiver home/digest); neutral proactive greeting ("你好呀…"); demo DB reset to an eligible invitation state; one-off capture/click/scroll scripts and temp files removed | full `verify.ps1` green: 283 backend, 116 flutter, Windows build, seed check |
| 2026-11-05T17:05+08:00 | M7 audit | Status audit: repaired `scripts/seed_demo.py` (whole file had been double-encoded GBK→UTF-8: mojibake + PUA chars, `SyntaxError` on line 44, `seed_demo --check` failing); `verify.ps1 -SkipBuild` green afterwards (backend 283, 99 flutter tests, seed check OK). Full `verify.ps1` build step currently fails only because a demo `anchor_app.exe` instance holds `mobile/dist/windows/*.dll`; close the app before the final gate. Screenshots 01–11 in `docs/img/` are captured; `docs/acceptance-checklist.md` still missing | `seed_demo --check` OK; `verify.ps1 -SkipBuild` = VERIFY GREEN; full build blocked by running exe |
| 2026-11-09T14:05+08:00 | M9 packaging | self-contained demo: `backend/app/entrypoint.py` + PyInstaller one-file `anchor_backend.exe` (12.3 MB, windowed, migrations/content bundled, demo auto-seed, DB next to exe) and `scripts/build_backend.ps1` / `test_backend_exe.ps1`; clean-dir smoke OK | 298 backend tests green at that point |
| 2026-11-09T14:10+08:00 | M9 autostart | app auto-starts the bundled backend: `BackendBootstrapper` (health probe → spawn `<exeDir>\backend\anchor_backend.exe` → poll 25 s), splash + retry card, kill-on-close job object; 27 tests; real E2E: double-click → health 200 in 6.6 s, close → 0 backend processes | 143 flutter tests green |
| 2026-11-09T14:20+08:00 | M9 real AI | real model + real speech, configurable in `Settings → AI 接入` and via `GET/PUT/POST /providers`: DeepSeek live reply (“好呀，我陪你聊聊。你阳台上那些花，最近开得怎么样？”); Windows SAPI ASR live transcript (“今天天气不错”); fake ASR only for tests; honest offline labels/disabled mic; keys masked | 347 backend + 159 flutter green; evidence in `docs/ai-live-evidence.md` |
| 2026-11-09T14:25+08:00 | final | packaged `AnchorDemo-0.2.0.zip` (43.8 MB): clean-room extract + double-click → backend auto-start → PUT DeepSeek key → real reply + real SAPI audio turn, close → port free; v0.2.0 release published; stale v0.1.0 removed | `verify.ps1` green: 347 backend, 159 flutter, Windows build, seed check |
