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
