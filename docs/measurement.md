> TA5 review update: test the current Windows senior controls in My choices.
> Test family setup and report retrieval separately on Android. Aided phone setup
> must not be counted as independent senior task completion. This protocol remains
> unexecuted until actual participant forms are supplied.

# Anchor — §8 measurement protocol (MANUAL — not yet measured)

This document defines how the user-study measures in guide §8 are collected. **No user study
has been run yet.** Every number below is therefore aspirational until the protocol is executed
and the raw forms are attached; nothing in this document reports a measured result. The
automated checks that back the corresponding behaviour live in `backend/tests/` and are mapped
in `backend/tests/test_acceptance_matrix.py`.

Status vocabulary used here and in the acceptance review:

- `NOT YET MEASURED` — the protocol exists, no participants have been run.
- `AUTOMATED EVIDENCE EXISTS` — a deterministic backend/source test covers the functional
  rule (this is evidence about the software, not about older adults' experience).

| Guide §8 area | Measurement | Target | Status |
|---|---|---|---|
| Proactive frequency | Invitations per local day and window compliance, from `checkin_events` | ≤1/day, none outside the window | AUTOMATED EVIDENCE EXISTS |
| Conversation naturalness | Participant rating after a scripted conversation | ≥4/5 | NOT YET MEASURED |
| Speech recognition | WER = (S+D+I)/N with the Mandarin tokenisation below, dialect groups separate | ≤20% pilot, ≤10% ideal | NOT YET MEASURED |
| First-use usability | Unaided task completion / attempted tasks | ≥70% initial, ≥90% ideal | NOT YET MEASURED |
| Approved memory | Correct recall after seven days, approved facts only | ≥90% | NOT YET MEASURED |
| Interaction controls | Scripted Stop/Not now cases reaching cancellation | 100% of scripts | AUTOMATED EVIDENCE EXISTS (backend); screen reachability still MANUAL |
| Sharing compliance | Permission-violation cases in the authorization suite | 0 violations | AUTOMATED EVIDENCE EXISTS |
| Digest quality | Two-rater conciseness/relevance rating | ≥3/5 initial, ≥4.5/5 ideal | NOT YET MEASURED |
| Diagnostic language | Digest items containing diagnoses or health scores | 0 | AUTOMATED EVIDENCE EXISTS |
| Family contact | Successful family-contact requests under this protocol | ≥80% | NOT YET MEASURED |
| Simple setup | Invite → consent → preferences completed | No complex configuration | AUTOMATED EVIDENCE EXISTS (functional flow) |
| Supplementary pilot measures | Companionship-without-surveillance, autonomy, caregiver reassurance, configuration time, voluntary sessions, family-call frequency | Descriptive only | NOT YET MEASURED |

## 1. Ethics and consent before any measurement

1. Use the older-adult consent form (`../04 老人测试与同意书.md` / `.docx`) and the caregiver
   consent form; record the signed version and date.
2. Assign a participant code (`P01`, `C01`) and use it on every form instead of a name.
3. Do not record audio longer than the task requires. Delete raw recordings once WER is scored,
   or keep them only if the consent explicitly allows it.
4. Stop immediately if the participant is tired, confused or unhappy; a stopped session is a
   valid data point ("not completed — participant declined"), never a failure of the person.

## 2. Speech recognition — WER with Mandarin tokenisation

### 2.1 Tokenisation rule (must be reported with the result)

Mandarin has no word delimiters, so the primary metric uses **character tokenisation**:

1. Normalise Unicode (NFKC), trim leading/trailing whitespace.
2. Remove all whitespace; every remaining character (including punctuation) is one token.
3. Apply exactly the same rule to the reference and the transcript.

If a word-segmented reference is used instead, run `--tokenizer space` and attach the
segmentation tool/version. Never mix the two tokenisations in one reported number.

### 2.2 Procedure

1. Fixed prompt set (≥30 utterances) covering: greetings, a meal, mood, an activity, a call
   request, a stop request, a repeat request, and one long sentence.
2. The facilitator reads the prompt as written; the participant speaks it once. Speech is
   captured through the same adapter used in the demo.
3. Save reference text and transcript as JSON, one record per utterance with `id`, `reference`,
   `transcript` and `dialect` (`mandarin`, `wu`, `yue`, …).
4. Score each dialect group separately; never average a small dialect group into Mandarin.

```powershell
# from anchor/
..\.venv\Scripts\python.exe scripts\eval_wer.py `
  --reference docs\data\wer-reference.json `
  --hypothesis docs\data\wer-transcript.json `
  --tokenizer char --group dialect
```

WER = (S + D + I) / N where N is the number of reference tokens. The script prints the overall
number, each dialect group, and raw S/D/I/N counts so the arithmetic can be re-checked.

### 2.3 WER observation form

| field | value |
|---|---|
| participant code | |
| device / microphone | |
| adapter and version | |
| tokeniser (char/space) | |
| dialect group | |
| prompt count | |
| S / D / I / N | |
| WER | |
| recording deleted (Y/N) | |

## 3. First-use usability — unaided completion

1. Tasks (one attempt each, no facilitator guidance): open the app; start a conversation; play
   one activity; call the saved family contact; stop the conversation; open My choices on the senior device; preview
   and approve a digest; delete one saved memory.
2. The facilitator may only read the task aloud once. A hint voids the attempt and is logged as
   "aided".
3. Completion rate = unaided completions / attempted tasks. Report failures by task.
4. Also record time to first successful conversation and any text-scale/contrast change needed.

### 3.1 Usability observation form

| task | attempted | unaided complete | aided | abandoned | notes |
|---|---|---|---|---|---|
| open app | | | | | |
| start conversation | | | | | |
| play activity | | | | | |
| call family | | | | | |
| stop conversation | | | | | |
| open My choices | | | | | |
| preview/approve digest | | | | | |
| delete memory | | | | | |

## 4. Approved memory — seven-day recall

1. During day 0 the participant proposes a fact and explicitly approves it (record the memory
   id and the approved wording).
2. Seven local days later, ask an open question that does not contain the fact ("What have you
   been enjoying lately?").
3. Score only facts the participant approved. Count a recall as correct when the stored fact is
   restated without the facilitator naming it. Partial recall is logged separately and is not
   counted as correct.
4. Do not infer memory ability from pauses, accent or session length.

### 4.1 Recall form

| memory id | approved fact (verbatim) | day-0 date | day-7 date | recalled? (Y/partial/N) | how it was retrieved | notes |
|---|---|---|---|---|---|---|
| | | | | | | |

## 5. Digest quality rating

1. The older adult previews the draft and approves the final wording (the backend records the
   approval and consent version).
2. Two raters (a caregiver and a researcher who did not write the digest) rate each delivered
   digest on a 1–5 scale for **conciseness** and **relevance**, then overall.
3. A digest containing a diagnosis, a health score or a risk label scores 0 and is reported as a
   privacy/language defect, not as a low quality score.
4. Report the mean of the two raters' overall scores and list every disagreement of ≥2 points.

### 5.1 Digest rating form

| digest id | period | items count | conciseness (1–5) | relevance (1–5) | overall (1–5) | banned language? | rater code |
|---|---|---|---|---|---|---|---|
| | | | | | | | |

## 6. Family contact success

Two different outcomes are reported separately; do not merge them:

1. **Interface reached** — the device opened the system telephone UI with the correct number
   (`tel:` URI). This is what the product can observe.
2. **Actual contact** — the family member confirms the call happened. Only the participant's or
   caregiver's confirmation counts; a dialer opening does not prove a conversation.

Procedure: the participant asks to call a saved contact (voice or one tap), confirms the call,
and the facilitator records whether the interface opened and whether the other person answered.
Success rate = interface-reached requests / requests, and separately confirmed contacts /
requests. Target: ≥80%.

### 6.1 Contact form

| participant | request | contact label | interface opened? | number correct? | confirmed contact? | notes |
|---|---|---|---|---|---|---|
| | | | | | | |

## 7. Supplementary pilot measures (descriptive)

- **Companionship without surveillance** — short interview quotes; no monitoring feed exists to
  evaluate because the product has none.
- **Autonomy** — number of sharing topics the participant turned off after the trial; whether
  they could explain how to revoke access.
- **Caregiver reassurance** — caregiver 1–5 rating of whether the weekly update was useful and
  calming.
- **Configuration time** — minutes from first launch to a completed invite + consent +
  preferences setup.
- **Voluntary sessions** — sessions per participant per week by `origin='voluntary'`.
- **Family-call frequency** — `contact_actions` rows per week, with `confirmed_at` counted
  separately from initiation.

## 8. Combining automated and manual evidence

The acceptance matrix test (`backend/tests/test_acceptance_matrix.py`) maps every guide §8 row
to either an existing automated test id or this protocol, and fails if a row disappears or a
referenced test no longer exists. Automated evidence may justify "the software does this";
it never justifies a performance or usability claim. Until forms in §2–§6 are filled in and
attached, every user-study row stays **not yet measured**, and any presentation must say so.
