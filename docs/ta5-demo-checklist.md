# TA5 rebuild and demonstration checklist

These source changes are integrated with the latest phone address editor in the alishcore/anchor-mvp fork. Existing release executables are older and must not be mistaken for the new build. Run the source with your team's configured test providers. No API key is included in the delivery.

## Apply and rebuild

Use a current checkout of https://github.com/alishcore/anchor-mvp. Do not apply the earlier chat patch again: these improvements are already included.

On Windows, with the repository's Python/Flutter prerequisites available:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/bootstrap.ps1
powershell -File scripts/package_windows.ps1 -Version 0.9.5-ta5
```

Use the newly generated package. The version above is a suggested local package name, not a published release.

For Android, replace `<computer-ip>` with the actual computer's reachable local address:

```powershell
. .\scripts\_common.ps1
Sync-MobileToAscii
cd "$env:LOCALAPPDATA\anchor-build\mobile"
flutter build apk --debug --dart-define=ANCHOR_API_BASE=http://<computer-ip>:8077 --dart-define=ANCHOR_DEVICE_ID=anchor-family-demo-1
```

The Windows default `anchor-win-demo-1` matches the seeded designated invitation device. Android should use a different identifier. If the computer IP changes, use Change the address on the phone login screen. Verify that saving and reopening the app retains the address on the actual Android device; automatic discovery and guided pairing remain future work.

## Configure and verify the actual devices

- [ ] Two devices are on a reachable local network; avoid guest Wi-Fi client isolation.
- [ ] Windows backend starts and is reachable from the phone on TCP 8077.
- [ ] Windows firewall allows the intended local connection.
- [ ] Log in using the seeded demo identities. The login is a development mechanism.
- [ ] Linked family account can configure providers on Android. Use test keys and keep them out of recordings and source archives.
- [ ] Windows microphone records a real utterance and a speaker audibly plays the response.
- [ ] Capture-to-caption and capture-to-first-audio times are recorded for several trials.
- [ ] Test Stop during capture, network processing, synthesis preparation and playback; no late reply restarts the interaction.
- [ ] Deny microphone permission once, then exercise Retry or typing.
- [ ] Open My choices directly from the senior home; no family phone is needed for sharing permission or deleting a memory.
- [ ] Create and accept an invitation on two devices if demonstrating a new relationship. Senior approval remains separate.
- [ ] Prepare last week's report. First-run synthetic data is already seeded by the packaged backend; the endpoint does not fabricate evidence. Insufficient data must stay insufficient.
- [ ] Cancel publication once. Verify the family cannot see an unpublished draft.
- [ ] Approve and share. Refresh the family app, select the week, and mark its generic reminder read.
- [ ] Repeated sharing does not create duplicate reminders.
- [ ] Revoke a topic, refresh family view, and confirm the topic disappears. Already seen/copied information cannot be recalled.
- [ ] Turn off all sharing using the confirmation dialog.
- [ ] Delete one synthetic remembered fact and verify it disappears.
- [ ] Confirm calling with an authorized number on the actual computer. Record dialer opening separately from an answered call. Never dial the seeded placeholder numbers.
- [ ] Disconnect the network and verify the UI explains recovery instead of claiming success.
- [ ] Test enlarged text and a narrow phone display; all required controls remain reachable.

The new on-demand generation/publication flow runs without a worker. Normal automatic weekly scheduling still needs `scripts/run_worker.ps1`. The phone polls for in-app reminders while open; it does not receive operating-system push notifications. Remote access is not implemented.

## Presentation evidence pack

- [ ] Record a 2–3 minute backup video from the new build.
- [ ] Save current home, conversation, My choices and family report screenshots.
- [ ] Keep synthetic data explicitly labelled in slides/narration.
- [ ] Add real participant results only after running the user-test protocol.
- [ ] Fill in actual team names and contributions in the 30-minute presentation guide.
- [ ] Have a facilitator, demo operator and slide operator assigned.
- [ ] Rehearse to 25 minutes plus five minutes of questions, unless your course allocates Q&A separately.

## Current boundaries

No rebuilt Windows executable or Android APK was produced on the macOS review host. Physical voice, LAN connectivity and calling need the checks above. The demo remains local-network-only, with development identity, HTTP and local plaintext provider keys. Do not use real participant data as if production safeguards were complete. Keep cloud-provider retention separate from local deletion claims.
