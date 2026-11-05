# Anchor — voice-first companion for older adults (MVP)

Anchor is a voice-first companion service for older adults living independently, with a caregiver
bridge that shares only what the older adult explicitly approves. It runs on ordinary phones and
tablets — no special hardware, no camera, no continuous room recording.

This repository implements the MVP specified in `../Anchor_Software_Design_and_MVP_Guide.md`.
The engineering contract is `SPEC.md`; the milestone ledger is `BUILD_PLAN.md`; the honest list of
what is **not** measured is `docs/limitations.md`.

## What is in the box

| Part | Path |
|---|---|
| FastAPI backend (auth, consent, conversation, activities, memories, digests, worker) | `backend/` |
| Flutter app — older-adult mode + caregiver mode | `mobile/` |
| Curated activity pack (trivia / stories / memory games) | `content/activities.json` |
| Setup, acceptance checklist, measurement protocol, limitations | `docs/` |
| One-command scripts (bootstrap, run, build, verify, seed, WER) | `scripts/` |
| Frozen contract + decisions log | `SPEC.md`, `DECISIONS.md` |

## Quickstart (Windows)

```powershell
cd anchor

# 1. Python environment (creates .venv, installs deps, migrates the DB)
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/bootstrap.ps1

# 2. Terminal A — backend on http://127.0.0.1:8077
powershell -File scripts/run_backend.ps1

# 3. Terminal B — worker (weekly digests, retention purge)
powershell -File scripts/run_worker.ps1

# 4. Terminal C — desktop app (builds first if needed)
powershell -File scripts/run_app.ps1
```

Seed the demo household before the demo:

```powershell
cd backend
..\.venv\Scripts\python.exe ..\scripts\seed_demo.py
```

Demo users: **1 = 林秀兰 (older adult)**, **2 = Mei (caregiver)**. The app's demo screen logs in by id.

## Five-minute demo script (what to click)

1. **Home** — three large buttons (Talk / Play / Call) plus Settings; the Stop/Not now bar is on every
   screen. Nothing else to learn.
2. **Invitation** — while the app is open inside the greeting window (and consent, quiet hours, cap,
   pause and designated device all allow it), Home offers a respectful “现在想聊聊天吗？” card:
   **聊一会儿** opens a proactive session and plays the greeting; **今天不用** records the dismissal
   and does not ask again today. Background OS notifications are a documented limitation.
3. **Talk** — `POST /sessions` opens a consented conversation; the mic indicator turns on, captions
   appear as you speak or type. Say “我今天吃了面条” → a short reply. Say “再说一遍” → the same
   answer. Tap **Stop** → the session ends immediately and late replies are discarded.
4. **Play** — “玩个游戏吧” (or the Play button) launches a trivia/story/memory activity from the
   curated pack; rotation never repeats until all items have been shown.
5. **Call** — “给儿子打电话” asks for one confirmation, then opens the system dialer with the saved
   contact; “Call to check in” on the caregiver digest points at the same saved number.
6. **Settings → Sharing topics** — every topic starts private. Toggle one, preview the weekly digest,
   edit a line, and approve it. The caregiver sees only the approved, permitted highlights.
7. **Caregiver mode** — invitation acceptance (invite → accept → senior approves), the weekly digest
   (≤ 3 supported highlights + Call to check in), and a proposed check-in schedule the senior must
   approve.
8. **Revoke / delete** — revoke access: every caregiver read returns 403 and unsent digests are
   cancelled. Delete my data: conversations, observations, memories and digests are removed and the
   consent version is bumped.

Screenshots of the running desktop app are in `docs/img/` (login, home, invitation window, talk, play,
call, settings incl. sharing topics, caregiver home, caregiver digest). They were captured from the
built executable against the live backend, not mocked.

## Repository docs

| File | Purpose |
|---|---|
| `SPEC.md` | frozen engineering contract (schema, API, consent rules, acceptance matrix) |
| `BUILD_PLAN.md` | milestone ledger + progress log with evidence per milestone |
| `DECISIONS.md` | append-only engineering decisions |
| `docs/setup.md` | providers, DB, worker recovery, retention/deletion, device setup |
| `docs/acceptance-checklist.md` | every §8/§9 item mapped to evidence or explicitly MANUAL |
| `docs/measurement.md` | pilot protocol for the manual rows |
| `docs/limitations.md` | honest list of what is not measured or not built |

## Verify

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify.ps1
```

Runs the backend test suite (including the eight required failure tests), `dart format`,
`flutter analyze`, `flutter test`, the Windows build, and the seed check. It must exit 0 before
anything is called complete. `docs/acceptance-checklist.md` maps every acceptance item to evidence.

## Honest limitations (short version)

No user study is included: naturalness, WER, unaided completion, digest quality and family-contact
rates are **not measured** — `docs/measurement.md` is the protocol, `docs/limitations.md` is the
disclosure. The speech adapter is replaceable but unevaluated with older-adult Mandarin; text
fallback is not the speech target; session credentials are in-memory; background OS notifications
are only partially wired on desktop; the demo form is a Windows laptop, not the target device.

## Demo environment note

The vault path contains non-ASCII characters, which crashes CMake 4.x and the Dart analysis server.
`scripts/build_windows.ps1` and `scripts/verify.ps1` therefore build and test from an ASCII mirror in
`%LOCALAPPDATA%\anchor-build\mobile`. This is a build workaround, not a product constraint — the
shipped source is the same.
