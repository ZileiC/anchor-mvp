# Anchor — voice-first companion for older adults (MVP)

Anchor is a voice-first companion service for older adults living independently, with a caregiver
bridge that shares only what the older adult explicitly approves. It runs on ordinary phones and
tablets — no special hardware, no camera, no continuous room recording.

This repository implements the MVP specified in `../Anchor_Software_Design_and_MVP_Guide.md`.
The engineering contract is `SPEC.md`; progress and the build ledger are in `BUILD_PLAN.md`.

## What is in the box

| Part | Path | Status |
|---|---|---|
| FastAPI backend + SQLite + worker | `backend/` | see `BUILD_PLAN.md` |
| Flutter app (older adult + caregiver modes) | `mobile/` | see `BUILD_PLAN.md` |
| Curated activity pack | `content/activities.json` | |
| Setup / acceptance / measurement docs | `docs/` | |
| One-command scripts | `scripts/` | |

## Quickstart (Windows)

```powershell
# 1. Python environment (creates .venv, installs deps, migrates DB)
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/bootstrap.ps1

# 2. Terminal A: backend  -> http://127.0.0.1:8077
powershell -File scripts/run_backend.ps1

# 3. Terminal B: worker (weekly digests, retention)
powershell -File scripts/run_worker.ps1

# 4. Terminal C: desktop app (builds first if needed)
powershell -File scripts/run_app.ps1
```

The demo seed (`scripts/seed_demo.py`) creates one older adult and one linked caregiver with
consented settings; run it after bootstrap.

## Verify

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify.ps1
```

`verify.ps1` runs the backend test suite (including the required failure tests), `flutter analyze`,
`flutter test`, and the Windows build. It must exit 0 before anything is called complete.

## Honest limitations

See `docs/limitations.md`. Short version: the speech provider adapter is replaceable but has not
been evaluated with older-adult Mandarin recordings (WER unmeasured); usability, digest-quality and
family-contact targets need the pilot measurement protocol in `docs/measurement.md`; session
credentials use an in-memory adapter pending mobile secure storage.
