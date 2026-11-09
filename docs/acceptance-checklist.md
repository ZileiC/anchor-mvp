# Anchor MVP — acceptance checklist

Source: `../Anchor_Software_Design_and_MVP_Guide.md` §8 (measurement) and §9 (final MVP checklist).
Status vocabulary: **MET** (automated evidence), **MANUAL** (needs a user study; no claim made),
**PARTIAL** (engineering path exists, end-to-end device behaviour unverified).

Reproduce everything with:

```powershell
cd anchor
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify.ps1
```

Latest run: `347 passed` (backend pytest) · `No issues found!` (flutter analyze) · `159/159` (flutter
test) · Windows build OK · seed check OK · packaged exe E2E verified (double-click → backend auto-start
→ real DeepSeek reply + real Windows SAPI transcript). Screenshots: `docs/img/01-login.png` …
`docs/img/11-settings-topics.png`; live AI evidence: `docs/ai-live-evidence.md`.

## A. §9 “Before calling the MVP complete” — all 13 items

| # | Item | Status | Evidence |
|---|---|---|---|
| 1 | Talk, Play, Call work on an existing phone and tablet | MET (layout) / MANUAL (device) | Widget tests `home_widget_test.dart::every primary action opens its screen in one tap` and the phone 390×844 / tablet 800×1200 layout tests; real desktop screenshots `02-home.png`, `03-talk.png`, `06-play.png`, `07-call.png`; backend flow tests `test_sessions.py::test_s2_*`, `test_s4_play_command_returns_activity`, `test_contacts.py::test_s11_*`. Physical Android device run not performed (see limitations). |
| 2 | Voice dialogue supports slow speech, captions, clarification, retry | PARTIAL | Captions/retry/one-clarification/confirmation paths: `test_sessions.py::test_s2_turn_produces_reply_and_captions`, `::test_s2_repeat_replays_last_answer`, `::test_s4_call_command_asks_one_clarification`, `::test_s6_session_view_includes_captions`, `test_s4_commands.py` (28 cases); app `talk_stop_test.dart`. Voice input is real on Windows via the local System.Speech recognizer (`backend/app/providers/asr_windows.py`, live transcript “今天天气不错” from a spoken WAV) and HTTP ASR can be configured (`/providers`); slow-speech tolerance, dialect coverage and WER remain MANUAL. Real LLM replies are live-verified after `Settings → AI 接入` (“好呀，我陪你聊聊。你阳台上那些花，最近开得怎么样？”); until configured the UI labels template replies as offline. |
| 3 | All three activity types work and rotate around chosen interests | MET | `test_activities.py::test_s3_content_pack_is_complete` (≥18 items, 3 types), `::test_s3_rotation_never_repeats_until_all_shown`, `::test_s3_rotation_survives_restart`, `::test_s3_interests_are_prioritised`; app `activity_rotation_test.dart` (10). |
| 4 | Memory is explicitly approved, inspectable, deletable | MET | `test_memories.py` (11): propose → approve → list → delete, `::test_memory_recall_7d`, `::test_failure_delete_memory`; UI at `11-settings-topics.png`. |
| 5 | Invitations respect opt-in, a daily cap, quiet hours, pause | MET | `test_checkins.py` 15 cases incl. `::test_s1_attempt_records_and_cap_blocks_second`, `::test_s1_quiet_hours_block_attempt`, `::test_s1_paused_and_snoozed_block`, `::test_failure_quiet_hours_midnight`; app `invitation_scheduler_test.dart` (22: window, midnight, cap, snooze, timezone, DST, restart) and `invitation_controller_test.dart` (16: eligible fires once, reasons suppress, dismiss not repeated, accept posts `accepted` + opens a proactive session); live screenshot `03b-invitation.png`. Background OS notification firing is not implemented (foreground path only). |
| 6 | Stop/Not now is visible everywhere and cancels active interaction | MET | Backend `test_sessions.py::test_s7_stop_purges_turns_and_is_idempotent`, `::test_s7_turn_after_stop_is_rejected`, `::test_s7_stop_command_inside_turn`, `::test_failure_stop_late_output`; app `talk_stop_test.dart::a late reply is discarded after Stop`, and Stop also kills the Windows SAPI speech child (`speaker_test.dart`); Home/Talk/Play/Call/Settings screenshots all show the bar; `home_widget_test.dart::home shows exactly three primary actions, Settings and Stop`. |
| 7 | No camera permission or hidden background recording exists | MET | `test_no_camera_capability.py` (4: Android manifests, Windows runner, plugin manifests; no CAMERA, no background-recording service), app `no_camera_test.dart` (5). |
| 8 | Every sharing topic starts private and remains under the older adult's control | MET | `test_consents.py::test_consents_are_private_by_default`; `test_authz.py` (37) incl. cross-household/client-supplied-id attacks; app `consent_privacy_test.dart` (5) renders the real Settings widget with private defaults; sharing toggles visible in `11-settings-topics.png`. |
| 9 | Caregiver setup follows invite, consent, and preferences | MET | `test_relationships.py::test_s12_invite_accept_approve_flow`, `::test_invitation_is_single_use`, `::test_invitation_expires`, `::test_approve_requires_pending_state`, `::test_schedule_proposal_approve_applies_preferences`; UI `08-caregiver-home.png`. |
| 10 | Weekly summaries use permitted evidence, senior approval, descriptive language | MET | `test_digests.py` 25 cases: adequate-data rule, ≤3 items with evidence ids, edit invalidates approval, consent filtering at read, banned-language rejection/fallback, insufficient-data message; UI `09-caregiver-digest.png` (3 highlights + honest privacy note). |
| 11 | Digest call actions and older-adult voice call requests reach the correct person | MET (dial URI) | `test_contacts.py::test_s11_senior_contact_action_returns_dial_uri`, `::test_s11_caregiver_can_call_linked_senior_contact`, `::test_s11_confirmation_is_recorded_separately`; `test_sessions.py::test_s4_call_command_requires_confirmation`; UI `07-call.png` and the call button in `09-caregiver-digest.png`. Actual phone contact is MANUAL. |
| 12 | Revocation, deletion, denied permissions, job recovery, offline behavior are tested | MET | Required failure tests below + `test_data_rights.py` (10: deletion counts, retention 35/180 days, memories kept until deleted, idempotent purge) + `test_worker.py::test_failure_worker_restart`, `test_authz.py` revocation cases, app offline test `home_widget_test.dart::offline Talk explains recovery and Stop still works`. |
| 13 | Pilot results distinguish achieved outcomes from aspirational targets | MET (documentation) | `docs/limitations.md` §1 table marks every user-study target **NOT MEASURED**; `docs/measurement.md` defines the protocol. This file never reports a user-study number. |

## B. §8 measurement rows

| Area | Target | Status | Evidence / why not measured |
|---|---|---|---|
| Proactive frequency | ≤ 1 opted-in invitation/day, none outside window | MET (rule) | `test_checkins.py` 15 cases; `invitation_scheduler_test.dart` 22 cases. |
| Conversation naturalness | ≥ 4/5 | **MANUAL — not measured** | Needs users rating real conversations; no study in this repo. |
| Speech recognition | WER ≤ 20% initial, ≤ 10% ideal | **MANUAL — not measured** | No held-out older-adult Mandarin/dialect recordings. Evaluator shipped: `scripts/eval_wer.py` (char tokenizer, dialect groups). |
| First-use usability | ≥ 70% unaided, ≥ 90% ideal | **MANUAL — not measured** | Needs observed first-use sessions; protocol in `docs/measurement.md`. |
| Approved memory | ≥ 90% correct recall after 7 days | MET (behaviour) / MANUAL (rate) | `test_memories.py::test_memory_recall_7d` with a frozen clock; the 90% user rate is not measured. |
| Interaction controls | Stop on every screen; cancellation in every scripted case | MET | `test_sessions.py` s7 cases + `talk_stop_test.dart` + screenshots. |
| Sharing compliance | 100% in the authorization suite | MET | `test_authz.py` 37 cases; `test_digests.py` caregiver filtering; `test_contacts.py` cross-household. |
| Digest quality | ≥ 3/5 initially, ≥ 4.5/5 ideal | **MANUAL — not measured** | Needs caregivers rating real digests. |
| Diagnostic language | Zero items with diagnosis or health score | MET | `test_digests.py::test_s10_banned_patterns_cover_the_spec_list`, `::test_s10_generation_guard_falls_back_to_safe_template`, `::test_s10_patch_rejects_diagnostic_language`; orchestrator also replaces diagnostic replies (`test_s2_diagnostic_reply_is_replaced`). |
| Family contact | ≥ 80% successful requests | MET (dial URI) / MANUAL (contact rate) | `test_contacts.py` s11 cases; "a dialer opening does not prove the family spoke" — actual contact is not measured. |
| Simple setup | Invite, consent, preferences without complex configuration | MET | `test_relationships.py::test_s12_invite_accept_approve_flow`; `test_preferences.py` 13 validation cases. |

## C. §8 required failure tests (all exist, all pass)

| Required test | Test id |
|---|---|
| Revoking a topic after draft generation blocks it at delivery and retrieval | `test_digests.py::test_failure_revoke_after_draft` |
| A caregiver cannot read another household's digest or change the senior's consent | `test_digests.py::test_failure_cross_household` (+ `test_authz.py` 37 cases) |
| Deleting a memory removes it from prompts and derived drafts | `test_memories.py::test_failure_delete_memory` |
| Stop during recognition/playback prevents late output from restarting | `test_sessions.py::test_failure_stop_late_output` |
| Quiet hours crossing midnight and time-zone changes create no extra invitations | `test_checkins.py::test_failure_quiet_hours_midnight` |
| Restarting the worker publishes no duplicate weekly digest | `test_worker.py::test_failure_worker_restart` |
| Sparse data produces an honest insufficient-information message | `test_digests.py::test_failure_sparse_data` |
| No internet: clear recovery without blocking Stop or system calling | `test_acceptance_matrix.py::test_failure_offline` (backend slice) + app `home_widget_test.dart::offline Talk explains recovery and Stop still works` |

## D. Control and privacy conditions (guide §8)

| Condition | Status | Evidence |
|---|---|---|
| Consent enforced before retrieval/transmission | MET | `test_digests.py::test_s10_caregiver_filtered_by_current_consent`, `test_sessions.py::test_s2_open_session_requires_cloud_consent`, `test_memories.py::test_memory_requires_consent`, `test_checkins.py::test_s1_consent_off_blocks_attempt`. |
| No transcript or audio content in audit rows | MET | `test_db.py` (audit-schema test), `test_sessions.py::test_s6_audio_turn_uses_transcript_without_persisting_audio`, `test_data_rights.py`. |
| Raw audio never persisted | MET | Orchestrator decodes in memory only; same tests above. |
| Caregiver scope limited to approved digest + contact call | MET | `test_sessions.py::test_s7_caregiver_cannot_read_conversation`, `test_memories.py::test_caregiver_cannot_read_memories`, `test_preferences.py::test_caregiver_cannot_read_or_patch_preferences`, `test_activities.py::test_s3_caregiver_cannot_read_activities`, `test_digests.py::test_s10_caregiver_never_sees_unapproved_digest`. |
| Versioned consent with conflict detection | MET | `test_consents.py::test_conflict_on_stale_base_version`, `::test_grant_bumps_version_and_writes_audit`. |
| Revocation immediately blocks and cancels unsent work | MET | `test_authz.py::test_authz_revoked_relationship_blocks_caregiver_actions`, `test_relationships.py::test_revoke_cancels_digests_and_notify_jobs`, `test_digests.py::test_failure_revoke_after_draft`. |
| Deletion request removes derived data and bumps consent version | MET | `test_data_rights.py` (10 cases). |

## E. What is deliberately not claimed

- No user-study numbers. Every usability/speech/digest-quality row above is MANUAL and in
  `docs/limitations.md`.
- No claim of dialect support (no recordings; `eval_wer.py` ready, data absent).
- No claim that background OS notifications fire on Windows/Android in this build
  (`InvitationScheduler` computes the plan and the app shows it; foreground greeting works).
- No claim of mobile secure storage (session token is in-memory for the app run).
- No claim that the Windows-laptop demo generalises to the target device form.
