# Slides 14–21 · spoken script

**Block:** Feasibility Assessment · 17:00 → 23:00 (six minutes, eight slides)
**You are on after** slide 13 (Windows host and Android client is *your* slide 14 — the previous presenter ends on the prototype conversation).
**You hand over to** slide 22, the live demo.

> The spoken script says **Everhere**. The deck footer on these eight slides still reads `ANCHOR / TEAM ONE` — change it or you will say one name while the screen shows another. That is the only fix I am asking for before you present.

---

## The logic you are carrying (say it once, at the start)

You are not walking through features. You are answering four questions in order:

1. **How does it run?** (14–15) — architecture, then the speech pipeline inside it.
2. **What can we prove?** (16–17) — a repeatable check, run on both platforms.
3. **What does a pilot need, and what does it cost?** (18–19) — operators, then money.
4. **Where does it stop being safe, and what is the gate before we demo?** (20–21) — limits, then readiness.

Each pair is *claim → evidence*. Nothing on 14–21 is a wish; every sentence is either how it works or what was measured.

---

## Slide 14 · Windows host and Android client — 17:00–18:00 (about 45 s, ~100 words)

> **Core:** one laptop is the whole product; the phone is a client that reads, never listens.

Everything sits on one machine. The Windows laptop runs two things: the Flutter interface the older adult touches, and the backend beside it — FastAPI with a SQLite database. The Android phone is a client. It asks the backend for the approved report and shows it; it never opens a microphone.

They talk over one trusted local network on TCP 8077, with UDP 8078 for automatic discovery — and if discovery fails, the family can type the address by hand.

Two honest costs of keeping the data in the home: the host has to stay on and reachable, and a *scheduled* weekly report needs a separate worker. Manual approval needs none.

**Bridge:** "That is the shape. Now inside that host — how a sentence gets in and a voice gets out."

## Slide 15 · Speech, captions and fallback — 18:00–19:00 (about 60 s, ~110 words)

> **Core:** every stage has a visible fallback, so a failure costs a step, not the conversation.

Four stages. **Speech recognition** turns audio into text, locally or through a configured cloud recogniser. **Conversation** takes that text — or typed text, which skips capture entirely — and the backend writes a reply. **Voice output** speaks it: the configured path can use DeepSeek, Microsoft Edge, or the device voice. And **recovery**: the caption stays on screen while audio is being prepared, Stop works at any point, and a retry is one tap once the service is back.

That is the design claim: an older adult should never be left looking at a dead screen. The screen keeps telling them what is happening.

**Bridge:** "We can describe that pipeline. The next two slides are about whether it actually holds."

## Slide 16 · What the backend smoke checked — 19:00–20:00 (about 60 s, ~110 words)

> **Core:** we wrote a repeatable check, and it tests the four things most likely to break quietly.

It is eight groups of checks against a real local socket and a temporary database, with synthetic records and test providers.

**Startup and roles** — the health endpoint answered, and a caregiver could not change the older adult's consent settings. **Conversation and Stop** — a synthetic voice turn returned a reply, and Stop still worked after consent was revoked. **Report access** — a caregiver asking for the draft got a 403; after the older adult approved it, the report was readable, and revoked highlights disappeared. **Provider failure** — a simulated outage returned a 503, and a typed retry succeeded.

The saved Windows evidence is on the slide.

**Bridge:** "Same script, two machines."

## Slide 17 · Backend smoke passed on both platforms — 20:00–20:45 (about 45 s, ~95 words)

> **Core:** 8 of 8 on macOS and 8 of 8 on Windows — and this is where the evidence stops.

The same script passed all eight groups on macOS and on Windows. The full automated suites — 442 backend tests, 319 Flutter tests, run on macOS — cover the rest of the behaviour.

Both runs used local HTTP, synthetic records and test adapters. So: repeatable backend behaviour, verified twice.

What this does **not** prove: a real microphone, a real speaker, or a real phone on a real network. Those are device questions, and they are the next two slides.

**Bridge:** "Which brings us to what a small pilot would actually need."

## Slide 18 · What a classroom pilot needs — 20:45–21:30 (about 40 s, ~85 words)

> **Core:** four things, all of them people or procedures — none of them new code.

A reachable Windows host: service and database on one laptop, with the network rehearsed. A way to handle provider failure: synthetic speech, typed input, a prepared walkthrough if the network drops. A report operator: seed the last completed week and check the first report before anyone watches. And, for anything ongoing, a schedule owner — manual publishing works without a worker; scheduled generation and retention need one.

That is the honest bar for "feasible in a classroom": we already own the equipment, and we can name the four jobs.

**Bridge:** "Cost is the other half of feasibility."

## Slide 19 · Illustrative monthly API costs — 21:30–22:05 (about 35 s, ~85 words)

> **Core:** about one and a half dollars a month for the API — a scenario, not a bill.

Under stated assumptions — ten cloud turns a day for thirty days, each turn one thousand input tokens, one hundred output tokens, fifty Chinese characters of speech — the API subtotal is about **US$1.48 per household-month**. Roughly eight cents of that is chat, one dollar thirty-five is speech.

It excludes electricity, connectivity, storage, support and retries, and nobody has been billed for this. The arithmetic and the dated rates are in the feasibility report; treat the number as an order of magnitude, not a quote.

**Bridge:** "Cheap and feasible are not the same as safe to distribute — and that is the last thing I want to be precise about."

## Slide 20 · Release and privacy limits — 22:05–22:25 (about 30 s, ~80 words)

> **Core:** three boundaries, two of them open and tracked.

**Windows packaging**: the current build script can embed a local credential file, so a build has to be inspected before it is distributed. **Cloud opt-out**: the direct speech endpoints need a server-side consent check before they call an external provider — that gap is open. **Deployment boundary**: this is a classroom build — demo identities, plain LAN HTTP, synthetic records only.

Both open items are pull requests, and neither is hidden.

**Bridge:** "So the last slide before the demo is the gate we hold ourselves to."

## Slide 21 · Readiness for a live demo — 22:25–23:00 (about 35 s, ~80 words)

> **Core:** four rehearsals before anything is shown live.

**Connection** — discovery *and* manual pairing, on the actual hotspot, not on a remembered network. **Speech and Stop** — real microphone, real captions, real playback, and the typed fallback practised. **Report workflow** — preview, approve, then refresh after revoking one topic. **Demo backup** — an English walkthrough ready if the connection or a provider fails.

We rehearse the failure paths, because those are the ones that decide whether the demo is honest.

**Hand-over to slide 22:** "Which is what we are about to do — live, on this laptop and this phone."

---

## Five answers you may be asked (keep them short)

**"Is this a medical device?"**
No. It is a companion for conversation and a weekly report. It never diagnoses, scores cognition or gives medical advice — that constraint is written into the prompt the model runs under, not just the UI.

**"Why not just a phone app for the older adult?"**
Because the family phone is where settings live, and a single small screen with one Talk button is the whole design for the person using it. Splitting the product was simpler than hiding controls from them.

**"Why is the host a laptop and not the cloud?"**
Privacy and cost. The database stays in the home and the API subtotal is about a dollar and a half a month. The price is that the laptop has to be on — we say that out loud rather than hide it.

**"What happens if the network dies mid-sentence?"**
Caption stays, Stop keeps working, and the retry is one tap. The typed path never needs the microphone.

**"Did real older adults use this?"**
Not yet, and we do not claim it. The participant protocol exists and the observation sheet is empty — that is a deliberate gap, not an oversight.

---

## Timing card (keep it visible)

| Slide | Window | Spoken |
|---|---|---|
| 14 | 17:00–18:00 | 45 s |
| 15 | 18:00–19:00 | 60 s |
| 16 | 19:00–20:00 | 60 s |
| 17 | 20:00–20:45 | 45 s |
| 18 | 20:45–21:30 | 40 s |
| 19 | 21:30–22:05 | 35 s |
| 20 | 22:05–22:25 | 30 s |
| 21 | 22:25–23:00 | 35 s |

If you fall behind, cut slide 19 to one sentence ("about a dollar and a half a month; the arithmetic is in the report") and give the time to 20 and 21. Never cut 20 — the limits are what make the rest credible.
