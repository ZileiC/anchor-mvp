# Anchor: delivery notes and next steps

Prepared 12 November 2026. This revision combines the TA5 improvements originally prepared against `86046d868d013cbd45cbc04a2db89059417590ec` with the newer `4adbffa633f48cee39f117f1268739be6b45436e` in https://github.com/alishcore/anchor-mvp. The existing phone backend-address editor is preserved. The original assignment files have not been edited.

## What changed

Both the UI and backend needed focused changes. The existing Flutter, FastAPI and SQLite architecture remains in place.

- The senior home now opens **My choices**: cloud permission, slower speech, invitations, observations, sharing topics, family connection, report approval and memory deletion.
- New senior-only endpoints prepare last week's report and publish it after approval. Existing permission, evidence and delivery services remain responsible for authorization and notifications.
- The family screen refreshes current permissions, offers a week selector and displays unread in-app reminders. The open family app polls every minute. There is no background push service.
- Conversation status now distinguishes the microphone, processing, speech preparation, playback and fallback. The idle microphone label no longer says it is listening.
- Calling explains the dependency on a system calling application. It does not add a telephony service.
- Android builds can set a separate `ANCHOR_DEVICE_ID` without editing source.

## What the rubric requires

The supplied rubric has four categories, each worth 3 marks, for 12 total. These materials support the criteria but cannot guarantee a score.

| Criterion | Evidence prepared | What the team must complete |
|---|---|---|
| Prototype communication | Product boundaries, feature explanations and a two-part demo plan | Demonstrate the revised build and clearly distinguish implemented features from future work |
| Usability explanation | Task examples, personal controls, recovery states and a blank observation protocol | Run observed tasks, explain specific interactions, and add genuine findings |
| Technical and operational feasibility | Existing architecture, authorization tests, setup responsibilities, deployment limits and cost inputs | Verify actual devices and network, record latency, assign support responsibilities and quantify usage/cost assumptions |
| Oral presentation | 30-minute running order, speaker notes, Q&A prompts and rehearsal checklist | Fill actual names/contributions, practice handoffs, voice, eye contact, timing and the backup demo |

## Team steps, in order

1. Clone or download the updated fork at https://github.com/alishcore/anchor-mvp. The earlier chat ZIP and patch target the older baseline and are not needed on top of this revision.
2. Rebuild Windows and Android using `ta5-demo-checklist.md`. Old repository executables do not contain these changes and must be rebuilt.
3. Configure the real test devices and providers. Demonstrate talk/Stop, senior approval, family viewing, revocation and a verified calling outcome. Record a short backup video.
4. Run the tasks in `ta5-user-test.md` with consenting participants. Record what happened without inventing percentages or quotations.
5. Fill team names and actual evidence in the presentation. The default allocation is 25 minutes including a 5-minute demo, plus 5 minutes Q&A. Use `ta5-presentation.md` for speaker guidance and alternate timing if Q&A is separate.
6. Rehearse on the real projector/network. Present the prototype's current limits honestly and explain which next improvement the observed evidence supports.

## Verification on this host

| Check | Result |
|---|---|
| Flutter tests | 293 passed after integration with the fork |
| Flutter analysis | No errors or warnings; 43 informational notices for the existing Material import deprecated by the newer test SDK |
| Backend tests | 402 passed; 2 failed because the original external guide is missing |
| New backend report-flow checks | Generation, publication, duplicate suppression, authorization, sparse data, local week boundaries and revocation covered |
| Source whitespace check | `git diff --check` passed |
| Physical Windows/Android behavior | Pending; not tested on this macOS host |
| Human usability study | Pending; forms are blank |

Backend command: `python -m pytest backend/tests -q` from the repository root, after installing `backend/requirements.txt` in a virtual environment. The two failing tests are `test_acceptance_matrix_covers_every_guide_area` and `test_acceptance_matrix_maps_every_required_failure_test` in `backend/tests/test_acceptance_matrix.py`. They expect `../Anchor_Software_Design_and_MVP_Guide.md`, which is absent from the repository. Restore the authentic original document before rerunning those checks. They have not been disabled or replaced with invented source material.

Flutter commands: `flutter analyze` and `flutter test` from `mobile/`. Validation used Flutter 3.50.0 / Dart 3.14.0 with that SDK's resolved test dependencies. The repository's original lockfile and generated Windows plugin list are retained to avoid an unrelated dependency migration. Resolve dependencies using the team's intended SDK and repeat target-device checks before release.

The source contains no new migration or external package dependency. The existing backend API remains available alongside the added endpoints. Synthetic widget previews in the presentation illustrate the UI using substituted test fonts; they are not physical-device screenshots or participant evidence.

## Material boundaries

No new Windows executable or Android APK was built here. No cloud-provider voice request, actual call, participant interview, remote deployment, or production security migration was performed. The current local prototype still uses development identity, HTTP and local provider credentials. Remote family access and system push require further engineering. Local deletion does not establish cloud-provider deletion.

The repository includes the improved source, timed speaker guide, rebuild/demo checklist and blank user-test protocol. The editable slide deck is delivered separately in the chat. Team names, device evidence and participant results remain deliberately unfilled.
