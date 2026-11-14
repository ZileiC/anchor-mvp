# TA5 automated verification record

Run on 15 November 2026 (Shanghai time) against upstream Anchor MVP
`019e5e0f42ff824faa394b399877239669be8906`. Host macOS arm64, Python 3.12.16, Flutter 3.50.0 / Dart 3.14.0.

| Command | Observed result |
|---|---|
| `python scripts/smoke_ta5.py --output docs/evidence/ta5-backend-smoke.json` | Exit 0, eight passing groups. A second isolated run produced identical results apart from the execution timestamp. |
| `python -m pytest backend/tests -q --tb=short` | Exit 0, 442 passed. |
| `flutter test --no-pub --reporter expanded` (from `mobile/`) | Exit 0, 319 passed. |
| `python scripts/seed_demo.py --check` | Exit 0, seed check passed and produced a valid weekly draft in a temporary database. |

The commands used the pinned backend requirements. The backend suite requires the original
`Anchor_Software_Design_and_MVP_Guide.md` beside the checkout and Flutter's resolved plugin
manifests in `mobile/.dart_tool`. Both were available for the run. Flutter 3.50.0 needed a local
dependency resolution with two changes to the committed lockfile. Those generated changes
are excluded from the evidence branch. Use the team's chosen SDK for Windows/Android builds.

## Reproduce the portable smoke test

From the repository root, activate a Python 3.10+ environment and install
`backend/requirements.txt` once. The smoke itself requires no Internet connection.

```text
python -m pip install -r backend/requirements.txt
python scripts/smoke_ta5.py --output ta5-backend-smoke.json
```

It starts the source FastAPI app with Uvicorn on an ephemeral `127.0.0.1` port, ignores
existing `ANCHOR_*` variables, and seeds an isolated temporary database at a fixed fixture
date. It uses synthetic audio, local rule replies, and injected failure adapters. It
does not call TTS, connect to a live provider or require provider credentials. The JSON
reports check status, safe HTTP status codes, source revision and the script hash.
The test exits nonzero on a failed check. The fixture date refers to the synthetic
report data, and the execution timestamp refers to the actual test run.

An isolation check also passed with outbound connections and DNS blocked beyond
loopback, a synthetic proxy and credentials set, and a decoy database path supplied.
The smoke left the decoy database untouched and omitted the sentinel values from its output.

## Verify the complete test counts

Place the authentic guide alongside the checkout. From `mobile/`, resolve packages using
`flutter pub get` and run the Flutter test command above. From the repository root,
run pytest and the seed check. These are software tests. Use the
[device readiness checklist](../ta5-demo-checklist.md) to collect physical and network evidence.
