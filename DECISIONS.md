# DECISIONS — append-only engineering log

Format: `## YYYY-MM-DD — title` / context / decision / consequences. Never delete a decision;
supersede it with a new entry.

## 2026-11-05 — Implementation contract frozen by the Lead

- **Context:** The guide asks for a proposal-level MVP; the build must be reviewable and testable
  without a user study. A fresh-agent build loop needs unambiguous contracts.
- **Decision:** `SPEC.md` is the implementation contract; `BUILD_PLAN.md` is the milestone ledger;
  `Anchor_Software_Design_and_MVP_Guide.md` remains the authority on product intent.
- **Consequences:** Contract changes require a new entry here + `SPEC.md` update; tests must never be
  weakened to fit code.

## 2026-11-05 — Identity: replaceable adapter, no password storage

- **Context:** Guide §5.1 says use a managed identity service.
- **Decision:** MVP ships a signed-token `DevIdentityProvider` (HMAC, dev-only login) behind an
  `IdentityProvider` protocol. No password column anywhere. Production OIDC is a documented TODO.
- **Consequences:** Endpoint tests mint tokens with the same secret; `ANCHOR_SECRET` must be rotated
  outside dev.

## 2026-11-05 — SQLite access via stdlib, sync, serialized

- **Context:** Small single-server pilot (guide §3.1).
- **Decision:** stdlib `sqlite3` with `check_same_thread=False` + a process-wide write lock, short
  transactions, `BEGIN IMMEDIATE` for job claims. No ORM.
- **Consequences:** All DB access goes through `app/db.py`; tests use a temp file DB (not `:memory:`
  where worker threads are needed) or a shared in-memory URI.

## 2026-11-05 — Injected clock and provider fakes

- **Decision:** `Clock.now()` everywhere; tests use `FakeClock`. ASR/LLM/Notifier are protocols
  injected into `create_app(settings, providers=...)`.
- **Consequences:** No sleeps in tests; timezone/DST and 7-day recall are directly testable.

## 2026-11-05 — Windows build workaround (environment, not product)

- **Context:** Workspace path contains non-ASCII characters; CMake 4.1 + cppwinrt crash there; the
  Windows runner's install step defaults to `C:\Program Files`.
- **Decision:** `scripts/build_windows.ps1` mirrors `mobile/` to `%LOCALAPPDATA%\anchor-build\mobile`,
  provides `nuget.exe` on PATH, forces `CMAKE_INSTALL_PREFIX` to the bundle dir, builds, and copies
  the artifact to `mobile/dist/windows/`. `mobile/windows/CMakeLists.txt` keeps the `if(TRUE)` fix.
- **Consequences:** Native build is reproducible on this machine; generated artifacts are gitignored.
  The demo form is a Windows desktop executable, as agreed in the TA5 war plan.

## 2026-11-05 — Observation topics and rotation state

- **Decision:** `preferences` stores `observation_topics` (JSON list, default all five when
  `record_observations` is enabled). Activity rotation state lives in a small
  `activity_rotation(senior_id, activity_type, last_index, updated_at)` table (added to
  migration 001) so it survives restarts.
- **Consequences:** `GET /activities` and `POST /activity-sessions` read/write rotation atomically.
## 2026-11-05 — Every Flutter step runs from the ASCII mirror

- **Context:** `flutter analyze` crashes the Dart analysis server with
  `FormatException: Unexpected end of input` because the LSP channel cannot parse the
  non-ASCII workspace path (`Ⅱ 26 Fall`). Previously only the Windows build was mirrored.
- **Decision:** `scripts/_common.ps1` gains `Sync-MobileToAscii`; `verify.ps1` runs
  `flutter pub get`, `flutter analyze`, `flutter test` and the build inside
  `%LOCALAPPDATA%\anchor-build\mobile`, and `build_windows.ps1 -NoSync` reuses that mirror.
  `dart format` still runs on the source tree (it handles the path correctly).
- **Consequences:** The gate is reproducible on this machine; the mirror is a build cache and
  stays gitignored. Nothing about the product changes.

## 2026-11-05 — Rotation timestamps are strictly increasing

- **Context:** Activity type rotation picks the least-recently-played type by `updated_at`.
  With the injected frozen test clock every play shared one timestamp, so trivia won every tie.
- **Decision:** `ActivityEngine` stores `max(clock.now(), latest+1s)` in `activity_rotation.updated_at`,
  making the ordering total without adding a schema column.
- **Consequences:** Rotation is fair under any clock resolution and still deterministic in tests.

## 2026-11-05 — Digest reads re-filter items; consent version is snapshotted at approval

- **Context:** SPEC §6.6/§7 require every caregiver read to re-check the relationship and
  `share_topic` consents, while an approval stores the consent version it was approved under.
- **Decision:** `DigestService._filter_items` drops any item whose topic is not currently permitted
  at read *and* delivery time. The digest row keeps the `consent_version` captured at approval for
  audit/UI, but filtering is driven by the current topic permissions, not by version equality:
  re-granting a topic before an unchanged version bump must not silently revive old items, and the
  topic check already covers every real permission change.
- **Consequences:** A stale digest never transmits a revoked topic; a later revision of the digest
  must be re-approved. Every edit deletes a queued `notify_digest` job so it cannot deliver stale
  wording.

## 2026-11-05 — Worker recovers crashed `running` jobs before claiming

- **Context:** SPEC §8 claim query selects `pending`/`failed` jobs; a process that dies mid-job
  would leave a row `running` forever and the lease would never be reclaimed.
- **Decision:** `JobRunner.run_once` first runs `recover_expired_leases`: expired `running` rows
  become `failed` with `last_error='lease_expired'`, then the normal claim query picks them up
  (one extra attempt, bounded by `max_attempts`).
- **Consequences:** Restart recovery matches the lease contract without changing the documented
  claim query; a test drives a `running` row with an expired lease and asserts exactly one reclaim.

## 2026-11-05 — Caregiver contact discovery via `GET /contacts`

- **Context:** Guide §5.7 says the caregiver digest's "Call to check in" action points at the
  older adult's saved contact, but SPEC §6.6 only lists `POST /contact-actions`, which needs a
  contact id the caregiver cannot otherwise learn.
- **Decision:** Add `GET /contacts` (SPEC §4 already permits the caregiver to read "the senior's
  saved contact for the digest call action"): a senior sees their own contacts; a caregiver sees
  only the linked, accepted senior's contacts. `POST /contact-actions` keeps the ownership checks.
- **Consequences:** The family-call button is implementable without leaking another household's
  contact list. New service modules `app/contacts.py` and `app/notifications.py` hold the logic;
  `app/jobs.py`/`app/worker.py` hold the queue per SPEC §1.

## 2026-11-05 — Local-date helpers must not treat a `datetime` as a Clock

- **Context:** `local_now`/`local_date_str` accepted "a moment or a Clock" and tested
  `hasattr(moment, "now")`. A `datetime` instance exposes the classmethod `.now`, so passing a
  datetime silently used the real wall clock — invisible while callers passed the injected Clock,
  but it broke the worker's scheduled week and retention cutoffs when called explicitly.
- **Decision:** Only call `.now()` when the argument is not already a `datetime`.
- **Consequences:** Both call styles behave as documented; the worker/retention tests now exercise
  a fake clock without escaping to real time.

## 2026-11-05 — Acceptance-harness decisions for M4

- **Context:** Some §8 measures are user-study measurements, and the mobile tree is owned by a
  different milestone; the no-camera test must not fail on a comment that says "no camera".
- **Decision:** (a) `test_acceptance_matrix.py` marks user-study rows `MANUAL`, maps them to the
  closest automated tests plus `docs/measurement.md`, and parses the guide §8 table and the eight
  required failure bullets so a missing row/test breaks the build. Manual measures are documented
  in `docs/measurement.md` (M8 owns `docs/acceptance-checklist.md`). (b) The no-camera scan strips
  XML/C comments and checks permission/feature/camera-API tokens, reading the declared `record`
  plugin manifest from `.dart_tool/package_config.json` because the microphone permission is
  supplied by that plugin. (c) `failure_offline` covers the backend-testable slice (structured
  provider recovery, Stop, local `tel:` action); screen-level offline behaviour remains M6.
  (d) `seed_demo.py --check` seeds a temporary database twice and generates a digest there, proving
  idempotency without touching `ANCHOR_DB_PATH`.
- **Consequences:** No measurement is faked; the suite documents exactly what is automated and what
  is still manual. Digest render counts are distinct observed days (the wording says "days"), not
  raw observation rows.

## 2026-11-09 — Real providers at runtime; "not configured" is an honest state

- **Context:** the demo shipped a deterministic rule LLM and a canned `FakeASR`, so "voice input"
  returned a fixed transcript even with nothing configured. A reviewer rightly called that fake.
- **Decision:** `GET/PUT/POST /api/v1/providers` (senior-only) manage a singleton
  `provider_settings` row (migration 002); effective providers resolve **stored row (URL+key) →
  `ANCHOR_*` environment → offline default**, so a `PUT` rebuilds `AppContext.providers` in place
  and the orchestrator picks it up with no restart (startup also rebuilds from the row). Notes:
  (a) explicit `ANCHOR_LLM_PROVIDER=none` / `ANCHOR_ASR_PROVIDER=none` build adapters that raise
  `provider_unavailable` with `recovery=["type_instead","configure"]`; (b) the ASR default is
  `none`, so `FakeASR` is never a silent default and stays test/injection-only; (c) the packaged
  `entrypoint.py` sets `ANCHOR_ASR_PROVIDER=auto`, which selects the real offline Windows SAPI
  recognizer when one is installed (else `none`); (d) `POST /providers/test` performs a real
  one-shot 10 s LLM call and a real ASR transcription when `audio_b64` is supplied.
- **Consequences:** The Settings screen must show `configured: false` honestly (LLM defaults to the
  offline rule engine, ASR refuses with a typed 503) until a real provider is entered/working.
  Keys are **stored in plaintext** in the local SQLite file — acceptable only for this self-hosted
  single-machine demo (documented in the migration); they are never logged or returned (the API
  only exposes `key_hint`). Audio still leaves only in memory; the SAPI path writes a temp WAV that
  is deleted immediately. One test contract changed on purpose: the default ASR is no longer
  `FakeASR`, and `test_frozen_paths` now sees migration 002.
