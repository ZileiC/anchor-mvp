# Anchor TA5 usability audit

Source walkthrough on 15 November 2026 against upstream `019e5e0`. These findings describe what the current interface does in code. Participant observation and Windows–Android rehearsal are pending.

| Priority | Journey | Baseline finding | Demo scope |
|---|---|---|---|
| 1 | Recover from a lost backend connection | Talk’s Retry calls the session opener, which returns immediately while offline. The message blames Internet access even when the Windows backend is the unreachable component. | Check the backend on Retry. Keep text editable while sending is unavailable. |
| 1 | View the weekly digest on Android | A refresh shows a spinner alongside prior highlights. After reconnecting, the previous offline warning can survive a successful digest read. | Replace cached highlights with labelled progress, then show the fresh result or a clear retry message. |
| 1 | Wait for an AI response | The spinner can sit beside the microphone-ready label. Mic and Send are still offered while the turn is pending. | Explain the wait in words and pause new input actions while keeping Stop reachable. |
| 2 | Recover when recognition fails | Provider errors offer retry or typing, but an empty capture can be silent and a mic start failure has no direct typing action. | Give capture failures a next step and reuse the existing typing field. |
| 2 | Start a conversation | The screen has a loading indicator, but its text says the microphone is opening while it is only opening a session. The mic control already explains when its provider is unavailable. | Correct the opening message as part of Talk feedback. Keep the large Talk entry and mic. |
| 2 | Stop an active interaction | Stop has a fixed position, shows a stopped panel, and the existing widget test discards a late reply. Physical capture and playback need rehearsal. | Preserve the control and verify it remains usable while waiting. |
| 3 | Review and approve sharing | My choices requires scrolling to the report. It already shows a preview, confirmation, progress and a shared result. | Rehearse this path. Keep the existing review and consent steps for TA5. |

## Before and after

1. **Talk feedback.** The opening status currently names the microphone and a pending reply can appear to invite a second turn. Show “Opening conversation…” and “Waiting for a reply” in the existing status area. Pause Mic and Send until the current operation settles. Keep Stop available.
2. **Talk recovery.** The offline Retry currently does nothing, and an empty capture may give no explanation. Recheck the connection on Retry. Offer “Try the microphone again” and “Type instead” after capture failure. Reuse the same screen and text field.
3. **Digest refresh.** The previous highlights stay visible during permission recheck, and a recovered connection can keep its warning. Show “Checking what is still shared…” until the digest fetch completes. Then render the current report or a retry action.

## Verification

The four regressions in [ta5_usability_test.dart](../mobile/test/ta5_usability_test.dart) simulate delayed replies, a lost and restored connection, microphone failure and an empty clip, and a caregiver report refresh. The full run on macOS passed 323 Flutter tests and 442 backend tests. Analysis reported 42 informational deprecation notices with zero warnings or errors. Physical microphone recovery, Android reconnection and participant task completion still need observation.

Use the [blank usability observation sheet](ta5-user-test.md#observation-form--copy-per-participant) with the rebuilt demo. Widget tests verify behavior with simulated devices and responses. They provide no participant results.
