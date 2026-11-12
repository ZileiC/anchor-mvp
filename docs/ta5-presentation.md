# Anchor — 30-minute presentation and speaker guide

Prepared for UCUG1907 Team Assignment 5. English. Replace the team number and member names before presenting. This is slide content and speaker guidance, not a record of completed user research.

Timing assumption: 25 minutes of presentation including a 5-minute demonstration, followed by 5 minutes of questions. If the instructor excludes Q&A from the 30 minutes, spend the extra five minutes on observed testing results and a second recovery demonstration. Do not fill time with unverified claims.

## Running order

| Slide | Topic | Time | Suggested presenter |
|---|---|---:|---|
| 1 | Anchor and the team | 1:00 | A |
| 2 | The person and situation | 1:30 | A |
| 3 | Design question and boundaries | 1:30 | A |
| 4 | Two devices, distinct responsibilities | 1:30 | B |
| 5 | Prototype capabilities | 1:30 | B |
| 6 | Senior conversation demonstration | 2:30 | B |
| 7 | Sharing and family demonstration | 2:30 | C |
| 8 | Usability choices | 2:00 | C |
| 9 | Design iteration and evidence | 2:00 | C |
| 10 | Recovery and user control | 1:30 | D |
| 11 | Technical feasibility | 2:00 | D |
| 12 | Operating the service | 2:00 | D |
| 13 | Cost and deployment assumptions | 1:30 | E |
| 14 | Evaluation and next iteration | 1:30 | E |
| 15 | What the prototype establishes | 0:30 | E |
| 16 | Questions | 5:00 | All |
| | Total | 30:00 | |

Presenters A–E are role placeholders, not assertions about the actual team size. Combine sections if fewer members present. Each person should understand the full flow.

## Slide 1 — Anchor

Visible: “A voice companion prototype for older adults living alone.” Team number, course, contributing members, and their actual contributions.

Speaker: “We explored how everyday conversation and family connection could become easier while keeping sharing decisions with the older adult. Today we will show the prototype, explain its usability, and assess what it would take to operate it outside this demonstration.”

Visual: the repository’s original Anchor logo. Keep its proportions. Do not read member names at length.

## Slide 2 — The person and situation

Visible: An older adult at home; family members are not always present; technical configuration can be a barrier. Label this as the **target scenario**, not a measured finding about all older adults.

Speaker: Describe a specific ordinary day. Distinguish the senior’s needs from the caregiver’s wish for reassurance. Use genuine interview evidence if the team has it. Otherwise explicitly say these are starting assumptions to test.

Audience engagement: “If someone else set up an app for you, which decisions would you still want to control yourself?” Take one brief response.

## Slide 3 — Design question and boundaries

Visible: “How might we make everyday conversation accessible while letting the older adult decide what family can see?” Below: conversation, optional activities, approved family updates.

Speaker: “The proposed value is companionship and a starting point for family contact. We have not established a reduction in loneliness or any clinical benefit. The prototype does not diagnose, assess cognition, detect falls, or provide emergency monitoring.”

Evidence: README and product boundaries. Do not present flower counts as cognitive measures.

## Slide 4 — Two devices, distinct responsibilities

Visible: actual senior home screenshot beside actual family setup screenshot. Label Windows senior device and Android family phone. Add: “Current prototype: same local network.”

Speaker: “The family configures the speech and conversation providers. The senior uses conversation and the new My choices area on their own device. The family cannot approve sharing on the senior’s behalf. A distant family member is part of the future use case; remote access is not implemented by the current LAN connection.”

Tradeoff: two devices simplify the daily interface but create setup and support work.

## Slide 5 — Prototype capabilities

Visible: a short status table with three categories: implemented in source; device verification pending; future work.

Implemented: conversation and in-chat activities; My choices; weekly draft generation; explicit publication; family update list and unread in-app reminders.

Pending: freshly rebuilt Windows/Android end-to-end run, physical sound and microphone behavior, actual family calling, user observations.

Future: remote secure access, production identity, background push, guided pairing.

Speaker: State the build/version being demonstrated. Never use an older prebuilt executable as evidence of new source changes.

## Slide 6 — Senior conversation demonstration (2:30)

Visible: live app or a recording of the exact build. Synthetic account label stays visible in the slide or narration.

Sequence: open home; identify Talk and My choices; start conversation; say a short ordinary sentence; point out Listening, Processing, voice preparation and playback states; show a caption; continue until an activity appears; answer or decline it; press Stop during an active step.

Speaker: “The user can see when the microphone is capturing. Waiting for recognition or speech output should not look like a frozen app. Stop cancels the current interaction.”

If the network stalls: allow a brief bounded retry, then use the backup recording and disclose it. Do not pretend a prerecorded response was generated live.

## Slide 7 — Sharing and family demonstration (2:30)

Sequence: My choices; show sharing topics; prepare last week’s update from synthetic observations; review the exact highlights; cancel approval once to show choice; approve and share; refresh the family app; open the update; mark an in-app reminder read; return to the senior screen and stop sharing a topic; refresh the family app and show the topic is absent.

Speaker: “Preparing a report does not share it. Publication is a separate decision. The family receives a short approved summary, not raw conversation or audio. Revocation blocks subsequent access, but cannot erase something already seen or copied.”

Explain that this demo publication is on demand, while scheduled operation still requires the worker. Reminders are foreground polling, not operating-system push notifications.

## Slide 8 — Usability choices

Visible: four annotated current screenshots, or two slides if projection readability requires it.

Talk: large primary target and short prompts. Captions: an alternative when audio is slow or difficult to hear. My choices: personal controls on the senior’s device. Confirmation: a pause before sharing or deleting.

Speaker: For each feature explain the intended benefit and a specific task. Large text is a design choice, not proof of accessibility. Check readability and touch targets with actual users and devices.

## Slide 9 — Design iteration and evidence

Visible: “Observation / change / next validation”.

Row 1: Repository reports an older adult struggling with technical settings; configuration moved to the family phone; validate setup with a caregiver.

Row 2: Repository reports confusion about a persistent Stop bar; Stop appears during interaction; validate that users can still find it when needed.

Row 3: Review identified that personal consent controls were inaccessible on the senior’s device; My choices added; test independent sharing and deletion.

Speaker: “The first two examples are informal observations reported in our project documentation. The third is a review-driven revision. We have not yet established the new design’s usability with participants.” Replace this with genuine dated findings only after completing the test protocol.

## Slide 10 — Recovery and user control

Visible: recognition failure, slow reply, no dialer, changed sharing choices.

Speaker: “Each failure should explain what happened and what the user can do next. We can retry or cancel voice interaction. Family calling hands a number to a configured system dialer; it does not itself implement a phone service. If no dialer is available, the number and an explanation remain visible.”

Show one current recovery screen. Never imply that an opened dialer proves an answered call.

## Slide 11 — Technical feasibility

Visible: Flutter clients; local Python/FastAPI service and SQLite; configured cloud speech/conversation services. Mark the cloud boundary and local-network boundary explicitly.

Speaker: “We reused existing backend permission and report services. The added endpoints prepare a completed week and publish a senior-approved report. Automated checks cover authorization, duplicate publication, sparse data, and revocation. They do not verify a physical speaker, microphone, or user comfort.”

Insert the actual verification results from the delivery notes. Describe any remaining failures precisely, including unavailable source documents or host-specific requirements.

## Slide 12 — Operating the service

Visible table: setup owner; daily operation; failure support; weekly updates; data choices.

Speaker: “A family member or facilitator initially installs and configures the system. The senior device must remain available, and the configured services require connectivity. Someone must handle updates, credentials and failures. Scheduled reports need a running worker; foreground reminders need an open app. These are operational responsibilities, not just software features.”

Current limitations: local network, no production authentication/TLS, debug builds, no guaranteed cloud availability. Give an owner and next step for each before suggesting a household pilot.

## Slide 13 — Cost and deployment assumptions

Visible: “Monthly cost = service usage + connectivity/hardware + support.”

Use a transparent worksheet on the slide:
- ASR: households × sessions/day × speech minutes/session × days × verified cost/minute.
- LLM: input/output token volumes × respective verified rates.
- TTS: characters generated × verified provider rate, if contracted.
- Support: setup hours plus recurring support hours × chosen labor assumption.

Speaker: “We have not measured steady-state usage or support effort. These are inputs to collect. A public voice endpoint without a service guarantee is not a dependable zero-cost production plan.” Do not insert invented vendor prices. An existing computer may lower initial spending, but its availability must be checked.

## Slide 14 — Evaluation and next iteration

Visible: tasks to test: start conversation; recover from an error; stop; review a report; revoke sharing; call family.

Speaker: “We will record unaided completion, time, requests for help, and what participants say. A small formative test identifies usability issues; it does not establish clinical effectiveness or universal accessibility. We will prioritize observed problems before adding features.”

Use the companion user-test form. Never turn target percentages in measurement.md into achieved results.

## Slide 15 — What the prototype establishes

Visible: a concise account of the demonstrated interaction, user control and remaining work.

Speaker: “The prototype makes the proposed interaction concrete and gives us a way to test it. Our immediate priorities are device verification and observed usability. Remote deployment, production security, and health-outcome claims require further work.”

## Slide 16 — Questions (5:00)

Have the responsible speaker answer first, then invite a teammate only if they add evidence. Keep one answer under about a minute.

Likely questions and answer boundaries:
- **Why Windows?** It is the implemented senior terminal. Convenience for development does not establish acceptance in the home.
- **Can family connect remotely?** Not with the current local-network architecture.
- **Who controls sharing?** The senior’s My choices screen plus senior-only backend authorization. Demo identity is not production authentication.
- **Has it reduced loneliness?** No such outcome has been measured here.
- **Does calling work?** State the tested device outcome. A tel link alone is not a completed call.
- **Does the app remember everything?** Explain explicit memory approval, observation permission, sharing topics and deletion separately.
- **Why not a generic assistant?** Explain the prototype’s focused interaction and sharing decisions as a design proposition, not proven superiority.
- **What did each teammate contribute?** Use actual tasks, artifacts and decisions. Do not equate commit count with all team contributions.

## Rubric coverage and rehearsal

Communication: slides 2–7. Usability explanation: slides 8–10 and task examples. Feasibility: slides 11–14. Oral presentation: the whole delivery.

Rehearse once for correctness, once on the real projector/network, and once to time. Assign one person to operate the demo and one to advance slides. Prepare a short recording, screenshots, and a clear fallback sentence. Speak toward the audience, use readable slide text, and do not spend the demonstration reading source code.

## Sources and evidence boundaries

Assignment template: Team Assignment 5 (3).pptx. Rubric: Team Assignment 5 Rubrics (2).xlsx, Sheet1 rows 2–5, four criteria worth 3 marks each.

Repository baseline: https://github.com/ZileiC/anchor-mvp/tree/86046d868d013cbd45cbc04a2db89059417590ec . Key evidence: README.md, HANDOVER.md, docs/measurement.md, and selected implementation files. The integrated revision in https://github.com/alishcore/anchor-mvp preserves the newer phone address editor and supersedes older descriptions of senior controls and on-demand publication. It does not establish human-study results or physical device reliability.
