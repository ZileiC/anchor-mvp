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

1. **Speech adapters are replaceable but unevaluated.** The offline default is a fake ASR used by
   tests; the hosted adapter is OpenAI-compatible but has not been benchmarked against older-adult
   Mandarin or dialect speech. Dialect support **cannot be claimed** from this build.
2. **Text fallback is not the speech target.** Typing into Talk recovers from a failed recognition,
   but it does not satisfy the one-sentence voice-access requirement in S4.
3. **TTS voice is not the target voice.** Device TTS (flutter_tts) is used on the demo machine; its
   timbre affects whether an older adult answers, so “answering rate” measured on a laptop is an
   artefact, not a product result.
4. **Desktop demo form.** The demo runs as a Windows desktop app; the target form is a phone/tablet
   (or fixed home device). Reactions to a laptop do not generalise, and the contradiction between a
   “high-risk older adult” who does not use a phone and this form is unvalidated.
5. **Credential storage is in-memory.** Session credentials live for the app run only. Mobile secure
   storage (Keystore/Keychain/DPAPI) is a documented adapter TODO, not implemented here.
6. **Invitations fire only while the app is open (foreground path).** The app polls check-in
   eligibility and offers the greeting card on Home inside the approved window; there is no
   local-notification plugin, so an invitation while the app is suspended/closed is not delivered.
   This is the guide §3.3 foreground allowance, not the background notification path.
7. **Windows speech is out-of-process.** `flutter_tts` crashed the Windows runner inside
   `flutter_tts_plugin.dll` (access violation 0xc0000005) on the first `speak()`. Windows now speaks
   through a short-lived PowerShell `System.Speech` child process (`WindowsSapiSpeaker`), which is
   verified on the built exe; Stop kills the child. The voice is therefore the OS voice (not the
   product's target voice), and Android's flutter_tts path is untested on a device.
7. **Proactive frequency is one opt-in invitation per day**, an explicit MVP resolution of the
   conflicting source targets (two/day minimum vs one/day cap). It does not claim the four-to-six
   initiation target; raising the cap requires user testing and the older adult's approval.
8. **Microphone capture depends on the `record` plugin and OS permission.** If capture is
   unavailable, Talk falls back to text; the mic indicator is then showing a text session, not audio.
9. **Worker is single-host.** SQLite + one worker suit a small pilot. Multiple workers on different
   hosts would race on the DB; move to a server database first.
10. **Deletion honours application storage, not provider copies.** Hosted ASR/LLM vendors may retain
    requests; say so in the consent copy and configure the vendor account accordingly.
11. **A caregiver cache cannot be recalled.** After revocation, future reads are blocked, but content
    a caregiver already saw or copied stays with them.
12. **No camera, no continuous recording, no diagnosis, no scores, no fall detection, no automatic
    emergency escalation** — by design. The manifest test asserts the camera-free surface.
13. **No user study is included in this repository.** The consent form and interview scripts live in
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
