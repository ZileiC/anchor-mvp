# Anchor MVP · TA5 feasibility evidence

UCUG1907 Design Thinking for Health Innovation · 15 November 2026 · Due 16 November 2026

**What the prototype establishes.** The single-host backend performed conversation and caregiver reporting with synthetic data. In the demo architecture it runs on the Windows laptop and serves the Android phone over the local network. The actual laptop, phone and presentation network still need a paired rehearsal. [Audited upstream revision `019e5e0`](https://github.com/ZileiC/everhere/commit/019e5e0f42ff824faa394b399877239669be8906)

## Technical evidence

| Evidence | Observed result | Scope |
|---|---|---|
| [Loopback backend smoke](evidence/ta5-backend-smoke.json) | **8 of 8 check groups passed on two fresh runs.** FastAPI started on a real local socket. Synthetic senior and caregiver roles were separated. An audio turn returned a stub transcript and local rule reply. Denied session turns stopped before ASR. Stop worked after revocation and cleared captions. Injected ASR/LLM failures returned 503. Typing recovered from ASR failure, and a fresh request worked after restoring the local LLM. | Uses a temporary SQLite database, seeded observations, a fixed clock, local-only HTTP and no live cloud providers. Startup here is a source-level test. |
| Same smoke run, weekly digest | The caregiver could not read the draft. Senior approval and repeat publication produced one readable report and one generic in-app reminder without a worker. A new caregiver fetch hid revoked highlights, and unlinking blocked direct access and removed the report from the list. | A fresh API read was observed. Android paint, open-screen refresh and behavior with a stale screen need device QA. |
| [Automated suites](evidence/ta5-automated-checks.md) | **442 backend tests and 319 Flutter tests passed** on macOS. Coverage includes authorization, Stop and late replies, consent, worker retry, sparse data, local discovery, and app routing/layout with substitutes. | Suite counts include unit, API and widget tests. They do not establish real microphone, speaker, firewall, Android or network behavior. |
| [Earlier voice engineering measurements](ai-live-evidence.md#voice-output-deepseek-tts-vs-edge-tts-measured-2026-11-14) | The repository records three provider synthesis trials per engine, measured from request to full audio body on 14 November. | Historical provider measurements. No current end-to-end or percentile latency, speech accuracy, reliability, participant or usability measurements were collected for this pack. |

## Operating model and demo gates

| Dependency or limit | Practical mitigation and owner |
|---|---|
| One Windows host runs the Flutter senior app, FastAPI and SQLite. Android is a setup and caregiver client. Discovery uses UDP 8078, and requests use TCP 8077. The developer launcher binds only to loopback. The packaged backend can listen on the LAN. | **Demo operator:** rehearse on a known private hotspot, check both ports on the actual devices, and practice the phone’s manual address using the Windows LAN address. Keep a short recorded backup if the link fails. |
| Voice relies on the Windows microphone and speaker, available Windows voices and configured providers. The current backend supports OpenAI-compatible ASR/LLM, DeepSeek TTS when configured, and Edge as cloud fallback. | **Device operator:** test capture, audible playback, Stop, denial/regrant, and typed captions on the actual Windows setup. Use only synthetic spoken material in any approved live-provider rehearsal. An ASR failure can be bypassed by typing when the LLM is available. |
| Manual digest publication works without a worker. Scheduled generation and retention use a separate worker on the same host/DB. Family reports and reminders are fetched in-app on open or refresh. | **Backend operator:** use a fresh synthetic database seeded on the demo day to avoid Monday week rollover, keep the host running, and use explicit Android refresh. Label the reminder as in-app. For scheduled operations, designate one worker owner and verify backup and recovery on the same host. |
| Current main has dev login, plain LAN HTTP, local plaintext provider settings, and unresolved release/consent defects. | **Release owner:** withhold the tracked Windows bundle, rotate affected keys, and verify an approved clean replacement before distributing it. Use synthetic data and a trusted LAN. The direct speech consent path requires review and verification on the selected build before making a broader privacy claim. [Packaging fix PR](https://github.com/ZileiC/everhere/pull/1) · [Speech-consent fix PR](https://github.com/ZileiC/everhere/pull/2) |

Use the [smoke reproduction steps](evidence/ta5-automated-checks.md#reproduce-the-portable-smoke-test)
and the [Windows + Android readiness checklist](ta5-demo-checklist.md). Log the actual build, devices,
network and fallback outcomes. Keep the local SQLite file, tokens, raw logs and keys outside the evidence pack.

## Running costs

**Measured spend.** The automated smoke made zero billable provider requests. No real invoice, sustained usage, electricity or support cost was measured.

**Illustrative monthly API estimate for one household.** Assume 30 days, 10 cloud turns/day, 1,000 uncached input tokens and 100 output tokens per turn, and 50 Chinese characters synthesized per turn. That is 300,000 input tokens, 30,000 output tokens and 30,000 billed TTS characters (two units per Chinese character). Assumptions include all turns using peak chat rates and no retries.

| Item | Public rate checked 15 November 2026 | Illustrative cost |
|---|---|---|
| DeepSeek Flash chat | US$0.30 per million uncached input tokens and US$1.20 per million output tokens at peak. [DeepSeek model pricing](https://api-docs.deepseek.com/quick_start/pricing/) | **US$0.126** |
| DeepSeek TTS | US$0.45 per 10,000 billed characters at list price. The estimate excludes temporary discounts. [DeepSeek TTS billing](https://api-docs.deepseek.com/guides/tts/#billing) | **US$1.35** |
| SiliconFlow Qwen3-ASR-1.7B | Listed as free at the time of review. Confirm plan eligibility, quotas and future rates before relying on it. [SiliconFlow pricing](https://siliconflow.cn/pricing) | **0 at the listed rate**, conditional on availability and eligibility |
| Host, connectivity and support | Reusing a laptop and phone can avoid a new purchase. Track host electricity, connectivity, backup storage and operator time. | **Unmeasured and excluded** |

The illustrative **US$1.48/month API subtotal** applies only to these assumptions. An invoice can differ with richer chat history, repeats, time of day, language and provider plan. For an operational estimate, record provider-billed units and operator time during a synthetic rehearsal and reprice them using the actual account terms.

## Mapping to TA5 Feasibility Assessment

| How the implementation addresses feasibility | Engineering evidence to present | Remaining evidence |
|---|---|---|
| The core workflow is implementable with the chosen components. | Show the two-device architecture and one local smoke result. Point out 403 for the unpublished draft and one reminder after repeated publish. | Run the actual Windows start → Android connect → report retrieval sequence. |
| The prototype handles predictable failures and controls access. | Show structured provider 503 → typed 200, Stop after revocation, and the caregiver re-fetch with filtered highlights. | Confirm recovery on hardware and explain the two open security fixes and the limit on previously viewed content. |
| The system can be operated within a small demo scope. | Name the host, network, provider and optional worker owners. Show fresh synthetic seed and repeatable pass/fail procedure. | Log install/reconnect time, the role handoff, device checks and backup outcome. |
| The cost assumptions are inspectable. | Show usage units, rate date and one representative arithmetic example. | Collect account usage, electricity and staff time before estimating real running cost. |

**Slide copy.** One Windows host, one Android caregiver phone, and a local backend. Eight automated workflow checks passed, including report approval, re-fetch after revocation and typed recovery from ASR failure. Live readiness depends on a clean package, a trusted LAN and device checks. The illustrative API subtotal is about US$1.48 per household-month under the stated assumptions, plus hardware, network and support.
