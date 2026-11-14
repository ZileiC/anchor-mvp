<p align="center">
  <img src="docs/assets/anchor-logo.png" alt="Anchor logo" width="150">
</p>

# Anchor

A companion for an older adult who lives alone.

It runs on two devices, on purpose. The computer in the living room is what the senior touches: one big circle, talk, listen. The phone belongs to the family. It holds the API keys and the model names, the family contacts, and the weekly digest. It never opens a microphone.

We took the settings screen off the computer and the voice off the phone after watching someone in their seventies hunt for a save button they did not need. Splitting the product was simpler than hiding things from them.

## What it does

Say "今天有点闷" and Anchor answers out loud. Speech goes to a cloud recognizer, DeepSeek writes the reply, and the voice is a neural one. The Windows SAPI voice sounded like a train announcement from 1998, so it is only a fallback now. The caption appears a couple of seconds before the audio starts, because synthesis takes three to seven seconds and pretending otherwise would just confuse people.

After the third exchange an activity turns up inside the conversation. Sometimes it is a question about kitchen safety. Sometimes it is a short story about a sewing machine, or a prompt about the dish their mother cooked. You answer by tapping or by saying it out loud. A right answer adds a flower to the count. A wrong one shows the right answer and explains why, and the word "wrong" is not used anywhere in the app. There is no score, no level, and nothing to compare with anyone else.

Calling family is one tap. Stop is visible only while something is actually running, and it disappears the moment the senior presses it. That was not the original design. The original kept a red stop bar on every screen and an elderly user asked why it was still stuck there after she had stopped.

## What it does not do

No camera. No continuous recording; the microphone opens only while a turn is captured, and a cancelled recording is deleted rather than left in `%TEMP%`. No diagnosis, no cognitive scoring, no leaderboards. The activity pack is conversation material, not a screening tool, and nothing in the interface calls it one.

## How the two halves connect

The backend runs on the computer and holds everything that matters: the SQLite database, the provider keys, the speech calls. The phone is a client. Both need to be on the same network, which in practice means the computer joins the phone's hotspot or the home Wi-Fi.

The phone's backend address is compiled in, not typed in, because typing an IP address is not something we want to ask of this user. Rebuild the APK when the address changes:

```powershell
. .\scripts\_common.ps1 ; Sync-MobileToAscii
cd "$env:LOCALAPPDATA\anchor-build\mobile"
flutter build apk --debug --dart-define=ANCHOR_API_BASE=http://<computer-ip>:8077
```

The packaged backend listens on `0.0.0.0:8077` so the phone can reach it. Windows Firewall needs one inbound rule for TCP 8077; the first connection usually triggers the prompt, and `HANDOVER.md` has the PowerShell one-liner for when it does not.

## Windows installation

Use a replacement ZIP verified by the project owner, or build a clean ZIP from
source using the steps below. The app starts its packaged backend automatically
and creates a local demo database on first launch. An installation from the
verified ZIP requires neither Python nor Flutter.

**Retire earlier Windows downloads.** Prior builds could contain recoverable
provider credentials. The GitHub source ZIP is a source download. See the
[Windows packaging and credential recovery instructions](docs/windows-packaging.md).

## Run it from source on Windows

```powershell
cd anchor
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/bootstrap.ps1   # venv, deps, migrations
powershell -File scripts/run_backend.ps1                                    # terminal A
powershell -File scripts/run_worker.ps1                                     # terminal B: weekly digests, retention
powershell -File scripts/run_app.ps1                                        # terminal C: the app
```

`run_app.ps1` builds the app if needed and now also builds the frozen backend if it is
missing — a missing backend is a hard error instead of a window that only complains.

The demo household is seeded on first run: user 1 is the senior, user 2 is the caregiver.
To build a self-contained ZIP locally:

```powershell
powershell -File scripts/package_windows.ps1 -Version local-demo
```

That produces `mobile\dist\AnchorDemo-<version>.zip` with the app and the frozen backend inside.
For a checkout with a cached backend from before the fix, use
`powershell -File scripts/build_backend.ps1` before running from source.

## Configure models and speech

All of it happens on the phone app now. The computer has no settings screen.

Chat uses an OpenAI-compatible endpoint. We run `deepseek-flash` at `https://api.deepseek.com` because it answers in about two seconds and the account exposes it.

Speech to text uses an OpenAI-compatible `/audio/transcriptions` endpoint. We use `Qwen/Qwen3-ASR-1.7B` on SiliconFlow: 0.52 to 0.65 seconds for a five-second clip in our measurements, against 2.9 seconds for the SenseVoice model we started with and occasional spikes past fifteen seconds. If your network prefers a different vendor, any compatible endpoint works; the adapter is one file.

Voice output goes through Microsoft's Edge neural voices via `edge-tts`. It is a public endpoint with no contract behind it. When it fails, the app falls back to the Windows system voice, logs that it did, and marks the attempt as degraded instead of pretending the good voice worked.

Enter your own provider keys through AI setup on the phone after installation.
Keys saved in the app live in the computer's local SQLite database, with masked
hints in API responses. Operators can also supply keys via the environment or an
external file at startup. A fresh install uses offline chat and attempts Windows
System.Speech recognition where available until ASR is configured.

## Tests

```powershell
.\ .venv\Scripts\Activate.ps1
python -m pytest backend\tests -q        # 399 backend tests
powershell -File scripts/verify.ps1      # backend tests, dart format, flutter analyze, 286 Flutter tests
```

Both are green right now. The Flutter tests run from an ASCII mirror (`%LOCALAPPDATA%\anchor-build\mobile`) because the repository path contains characters that crash the Dart analysis server on this machine; `scripts/verify.ps1` handles the sync.

Green tests are not the same as a working product. We learned that the hard way: 286 tests passed while the audio path was silently broken, because no test can hear a speaker.

## Where to look

| File | What is in it |
|---|---|
| `SPEC.md` | the engineering contract, still the reference for endpoints and invariants |
| `BUILD_PLAN.md` | milestone ledger |
| `docs/limitations.md` | what is measured and what is not, written to be uncomfortable |
| `HANDOVER.md` | how the two-device split works, and the weekly report work still open |
| `docs/design/senior-ui.md` | the senior interface design: colours, type, layout, motion |
| `docs/acceptance-checklist.md` | manual checks before a demo |
| `docs/measurement.md` | the pilot protocol |

## Known limits

This is a course deliverable, not a shipped medical product. There is no TLS anywhere, login is a dev endpoint that takes a user id, the APK is debug-signed and about 150 MB, and the weekly report does not yet have a generate endpoint or a caregiver inbox in the app. `HANDOVER.md` section 6 lists all fourteen, including the ones that will bite during a live demo.

## Team

Built for TA5 of 1907 Design Thinking for Healthcare Innovation. Workflow notes are in `CONTRIBUTING.md`; the repo is public and `main` is integration-owned.
