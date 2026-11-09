# Anchor MVP — honest limitations

The guide is explicit: performance targets “require measurement with users and should never be
presented as guaranteed results of selecting a technology”, and pilot results must “distinguish
achieved outcomes from aspirational targets”. This file is the single place where that distinction
is recorded. Nothing below is met just because the code exists.

## 1. Not measured yet (needs the pilot protocol in `measurement.md`)

| Target (guide §8) | Status | Why |
|---|---|---|
| Conversation naturalness ≥ 4/5 | **NOT MEASURED** | needs users rating real conversations |
| Speech recognition WER ≤ 20% initial, ≤ 10% ideal | **NOT MEASURED** | no held-out older-adult Mandarin/dialect recordings; only a fake ASR adapter and an evaluator script exist |
| First-use usability ≥ 70% unaided, ≥ 90% ideal | **NOT MEASURED** | needs observed first-use sessions without facilitator guidance |
| Approved memory recalled ≥ 90% after 7 days | Automated behaviour verified; **user-study rate NOT MEASURED** | a frozen-clock test proves retrieval after 7 days, not the user outcome |
| Digest quality ≥ 3/5, ideal ≥ 4.5/5 | **NOT MEASURED** | needs caregivers rating real digests |
| Family contact ≥ 80% successful requests | Only dial-URI resolution verified; **actual contact NOT MEASURED** | a dialer opening is not proof that a family conversation happened |
| Companionship / autonomy / caregiver reassurance | **NOT MEASURED** | qualitative pilot outcomes |

The required failure tests in `backend/tests/` do pass (revocation, cross-household, deleted memory,
late output after Stop, quiet hours across midnight, worker restart, sparse data, offline recovery).
Those are engineering controls, not evidence about older adults.

## 2. Product/technology limitations

1. **Speech adapters: real but not benchmarked.** The Windows default is the local System.Speech
   recognizer (`windows-sapi`) — genuine recognition, no key, but it cuts at pauses, has no dialect
   tuning and in practice often returns nothing for real Mandarin, so it must not be presented as
   working voice input. Entering `asr_base_url` + `asr_api_key` + `asr_model` under
   `Settings → AI 接入` switches to any OpenAI-compatible `/audio/transcriptions` endpoint
   (`HttpASR`); the wiring and its 503/401 paths are unit-tested, but **no vendor key has been run
   end-to-end on this machine yet** — until one is, voice input stays unverified. WER and dialect
   support **cannot be claimed** from this build; text fallback is still not the speech target.
2. **The LLM is a real model only after it is configured.** Default `rule` replies are deterministic
   templates; the UI labels them “离线模板回复”. `Settings → AI 接入` connects a DeepSeek/OpenAI-
   compatible endpoint (live-verified on this machine: “好呀，我陪你聊聊。你阳台上那些花，最近开得
   怎么样？”). Until a key is entered, no claim of model quality should be made.
3. **Provider keys are stored in plaintext** in the local SQLite file for this self-hosted demo;
   never distribute `backend/data/anchor.db` with a key inside. The API masks keys and never logs
   them.
4. **Desktop demo form.** The demo runs as a Windows desktop app; the target form is a phone/tablet
   (or fixed home device). Reactions to a laptop do not generalise, and the contradiction between a
   “high-risk older adult” who does not use a phone and this form is unvalidated.
5. **Credential storage is in-memory.** Session credentials live for the app run only. Mobile secure
   storage (Keystore/Keychain/DPAPI) is a documented adapter TODO, not implemented here.
6. **Invitations fire only while the app is open (foreground path).** The app polls check-in
   eligibility and offers the greeting card on Home inside the approved window; there is no
   local-notification plugin, so an invitation while the app is suspended/closed is not delivered.
   This is the guide §3.3 foreground allowance, not the background notification path.
7. **Windows speech is out-of-process and network-bound.** `flutter_tts` crashed the Windows runner
   inside `flutter_tts_plugin.dll` (access violation 0xc0000005) on the first `speak()`, so Windows
   never calls it. Each utterance is now `POST /api/v1/tts` to the local backend, which synthesises
   with `edge-tts` (Microsoft Edge neural voices: default `zh-CN-XiaoxiaoNeural`, rate −12% for older
   ears) and returns MP3; a short-lived PowerShell `MediaPlayer` child plays the file, and Stop kills
   it. Verified on the installed exe on 2026-11-09: a 12-character Chinese reply produced a 15,840-byte
   MP3 that played for 4.27 s and was then deleted. Two costs it does not hide: synthesis needs
   internet and takes ~3–7 s per sentence (measured through the frozen exe: 30 chars → 6.6 s, 34
   chars → 6.9–7.1 s), and the spoken text leaves the machine to Microsoft's Edge service — this is a
   demo-grade voice, not a contracted TTS vendor. On any failure the app falls back to the Windows
   SAPI voice (`System.Speech`): audible, robotic, and `lastAttemptFailed` then reads `true`. Android's
   flutter_tts path is still untested on a device.
8. **Proactive frequency is one opt-in invitation per day**, an explicit MVP resolution of the
   conflicting source targets (two/day minimum vs one/day cap). It does not claim the four-to-six
   initiation target; raising the cap requires user testing and the older adult's approval.
9. **Microphone capture depends on the `record` plugin and OS permission.** If capture is
   unavailable, Talk falls back to text; the mic indicator is then showing a text session, not audio.
10. **Worker is single-host.** SQLite + one worker suit a small pilot. Multiple workers on different
    hosts would race on the DB; move to a server database first.
11. **Deletion honours application storage, not provider copies.** Hosted ASR/LLM vendors may retain
    requests; say so in the consent copy and configure the vendor account accordingly.
12. **A caregiver cache cannot be recalled.** After revocation, future reads are blocked, but content
    a caregiver already saw or copied stays with them.
13. **No camera, no continuous recording, no diagnosis, no scores, no fall detection, no automatic
    emergency escalation** — by design. The manifest test asserts the camera-free surface.
14. **No user study is included in this repository.** The consent form and interview scripts live in
    the TA5 materials; the measurement protocol here is the engineering half only.

## 3. Environment caveats (build, not product)

- The vault path contains non-ASCII characters; CMake 4.x and the Dart analysis server crash there.
  All Flutter verification/builds run in an ASCII mirror (`%LOCALAPPDATA%\anchor-build\mobile`).
  This is a build-environment workaround, not a product constraint; the shipped artifacts are the
  same source.
- `flutter_tts`'s Windows CMake requires `nuget.exe`; `scripts/build_windows.ps1` downloads it.
- The Windows TTS crash (0xc0000005 in `flutter_tts_plugin.dll`) is why Windows uses the SAPI child
  process; the plugin stays in `pubspec.yaml` only for mobile. A debug build keeps Dart code in
  `data/flutter_assets/kernel_blob.bin`, so the exe timestamp alone is not proof of a code change.
- Demo data is synthetic. Names, phone numbers and observations in `scripts/seed_demo.py` are
  fabricated for demonstration and must never be presented as real participant data.

## 4. What the build does demonstrate

- Consent is enforced before retrieval/transmission, with versioned conflicts and audit trails.
- A caregiver cannot read conversations, another household's digest, or private topics.
- Invitations respect window, quiet hours (including midnight crossing), daily cap, pause, snooze and
  the designated device.
- Stop cancels immediately and a late model answer cannot resume the interaction.
- An approved memory survives seven days; a deleted fact never reaches the prompt.
- A digest contains at most three supported items, all with evidence, and no diagnostic language.
- Restarting the worker does not duplicate a digest or notification.
- Sparse data produces an honest “not enough information” message instead of filler.
