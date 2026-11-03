# Findings — issues hit while building this demo, and how they were fixed

The honest record of what didn't work first try (or isn't fully live) and what we
did about it. Mirrors goat's findings discipline. Nothing here is a
blocker for the two headline operations — **rotate** and **revoke** are both
backed by built `goat` commands (ADR 1044 / ADR 1031) and run end-to-end in this
repo.

---

## AM-1 — the health gauge color is window-jitter-sensitive near the target

**What we saw.** With the flooder at 350 msgs/s into a demo C2 target of 300, the
5-second health window landed sometimes RED (e.g. 326/300) and sometimes AMBER
(e.g. 267/300) across otherwise identical runs. The averaging window plus laptop
scheduler jitter means a rate *just over* the target doesn't reliably clear it
every window.

**Why it's not a bug.** This is the meter being *honest*: it colors on what it
actually measured in the window, and a marginal rate is marginal. "Off green"
(AMBER **or** RED) is the real detection signal; the exact shade near the line is
genuinely indeterminate.

**Fix.** (1) Raised the demo flood rate to **450 msgs/s** (target 300) so it
clears with margin and lands RED far more reliably for the report. (2) Kept the
scenario assertion tolerant — it checks for AMBER **or** RED, not RED only, so a
jittery window never produces a false failure. Robustness, not a cover-up.

---

## AM-2 — the throughput-envelope BAND has no portal locally (represented, not live)

**What we saw.** `goat top` renders an actor's band (LOW/normal/HIGH/**OVER**) by
fetching the declared `{min,mean,high,max}` envelope from the **portal registry**
(ADR 1045). The self-contained local fabric runs a router + meter but **no
portal**, so `goat top` has no envelope to judge against and shows `—`.

**Impact on the demo.** The *rate* and the *OVER verdict* in scenario 03 are
real (read from the live per-producer footprint); only the *declared registry* is
represented — the scenario computes the band from the footprint rate vs a stated
`max ≈ 50` and labels this honestly (`honesty:` lines + the honesty matrix).

**Fix / options.** Left represented for v1 (the rate-based detection is genuine
and sufficient to drive the revoke decision). A durable upgrade — a tiny static
mock portal serving `GET /api/envelopes` so `goat top` renders the band live — is
a clean follow-on and is noted in the honesty matrix; it does not change the
rotate/revoke arcs.

---

## Non-findings (things that worked first try, recorded so the absence is honest)

- Per-slot ACL scoping: a leaf writing another slot's anchor was denied on the
  first attempt (scenario 01) — the pre-cut grant is genuinely slot-bound.
- Rotation config-stability: the router `config.json5` hash is **byte-identical**
  before and after a rotation (scenario 02) — the ACL truly isn't touched.
- Revoke denial: after the slot reclaim, a real observer saw **0** samples from
  the offender (scenario 04) — the cut is real, not narrated.
