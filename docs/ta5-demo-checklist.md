# Anchor TA5 · Windows + Android readiness checklist

Run with the actual presentation laptop, Android phone, projector and network before 16 November 2026. Record pass, fail or pending for each gate. The saved [backend smoke](evidence/ta5-backend-smoke.json) is automated source-level evidence.

| Record before starting | Fill during rehearsal |
|---|---|
| Date/time (Shanghai), operator names | |
| Source commit, Windows package SHA-256, APK SHA-256 | |
| Windows version, mic/speaker, Android model/version | |
| Network and connection method, selected fallback | |

## 1. Prepare the build and demo data

- [ ] Confirm the reviewed Windows package and exact Android APK. The tracked Windows bundle on the audited revision is affected by credential exposure. Use a verified replacement after the release owner rotates affected keys and reviews the packaging fix. [Packaging PR](https://github.com/ZileiC/anchor-mvp/pull/1)
- [ ] Agree what will be demonstrated with the selected build. Verify the direct speech consent fix before relying on cloud opt-out in a live cloud-voice demonstration. Use a trusted LAN and synthetic data for all demo paths. [Speech-consent PR](https://github.com/ZileiC/anchor-mvp/pull/2)
- [ ] Run the [reproducible backend smoke](evidence/ta5-automated-checks.md#reproduce-the-portable-smoke-test) and attach its JSON. The build operator prepares a fresh synthetic database for the actual demo date. On Monday 16 November, the expected previous completed week is 9–15 November local time. Use a separate database for rehearsal so the live report stays unpublished.
- [ ] Store keys only in local runtime settings. Keep keys, local databases, tokens, raw recordings and diagnostic logs out of the slides and shared files. Keep the app closed while switching database files.

For a reviewed source checkout with Flutter and the Windows build tools, use the project [setup runbook](setup.md). The reviewed packaging procedure produces the Windows ZIP. Build the Android APK from the Flutter source using the existing Windows ASCII mirror:

```powershell
. .\scripts\_common.ps1
Sync-MobileToAscii
cd "$env:LOCALAPPDATA\anchor-build\mobile"
flutter build apk --debug
```

Install the APK from `build\app\outputs\flutter-apk\app-debug.apk`. The login screen supports discovery and a manual Windows LAN address. A fixed address can also be supplied at build time with `ANCHOR_API_BASE` when required.

## 2. Verify launch, reachability and roles

- [ ] Cold-start Windows Anchor. Confirm the bundled backend comes up and `http://127.0.0.1:8077/api/v1/health` returns `status: ok`. Confirm the phone can reach the same API using the Windows LAN address.
- [ ] Use a private hotspot or trusted Wi-Fi without client isolation. Permit TCP 8077 on that network. If testing discovery, verify UDP 8078. Reopen the Android app and confirm discovery or the saved address. Rehearse manual entry of the current LAN address if discovery fails.
- [ ] Use the synthetic senior account on Windows and linked caregiver account on Android. Confirm Talk and My choices on Windows, and family setup and weekly report on Android. Confirm ordinary Android setup shows no mic prompt.

## 3. Verify the two presentation paths

- [ ] **Conversation.** Use a short synthetic utterance on Windows. Check visible caption and audible reply separately. Try mic denial/regrant and typed recovery. Exercise Stop during capture, processing and playback, and observe whether any late output appears.
- [ ] **Report.** On Windows, generate the last completed week in My choices. Preview the synthetic report. On Android, refresh before approval and verify there are no visible draft highlights. On Windows, approve and share. Open/refresh Android and verify the week, highlights and generic in-app reminder.
- [ ] **Revocation and refresh.** Revoke one published topic on Windows. Explicitly refresh the Android report and confirm that highlight disappears. Briefly disconnect Android and observe what the screen shows. Reconnect and verify a fresh read. Record the API and the display outcomes separately.
- [ ] **Recovery.** If ASR fails, demonstrate typing with a reachable backend and a working chat provider. If the LAN or chat path fails, use the prepared recording of a verified run. Demonstrate the call button only if rehearsed with an authorized number. Record dialer launch and answered call separately.

## 4. Evidence and sign-off

| Test | Operator | Pass / fail / pending | Observed result or sanitized artifact |
|---|---|---|---|
| Cold launch and Android connection/reconnect | | | |
| Mic recovery, caption and audible playback | | | |
| Stop during capture, processing and playback | | | |
| Review, publish, in-app retrieval and revocation/refresh | | | |
| Projector and backup recording | | | |

- [ ] Record actual timings only if measured. For voice, mark speech end, first caption and first audible output separately and include network, device, provider mode and trial count.
- [ ] Label synthetic report content and distinguish device QA from participant observations. Use the [formative user-test protocol](ta5-user-test.md) for any separately consented usability session.
- [ ] Name the Windows operator, Android operator and backup-video operator. Confirm the chosen live path before presenting. Manual report publication works without a worker. Scheduled generation and retention require a separate worker. The report is refreshed in-app.
