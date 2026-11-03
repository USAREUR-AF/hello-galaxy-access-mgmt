# Detect the spammer — three honest detection signals

Before you can revoke a misbehaving actor you have to *find* it, and be sure.
A flooding producer is the common case (usually a bug, sometimes hostile), and
the fabric surfaces it three complementary ways — all read-only, all honest.

`loud-mouth` starts flooding the situational lane. We detect it with:

1. **The health gauge** (`goat health`) — per-class load vs a capacity target,
   coloured green/amber/red, with an `n` sample count so a verdict is only shown
   when it's grounded in real traffic (never a false green). The flood drives the
   gauge off green.

2. **The per-producer footprint** (`goat health --peer <anchor>`) — ranks every
   producer by rate and flags the one that's **near-limit**. The flooder shows up
   as **rank #1**, owning the lane. This is the attribution the gauge can't give
   you: *which identity* is responsible.

3. **The throughput envelope band** (`goat top`) — each registered actor has a
   declared expected range `{min, mean, high, max}`; a producer past its `max`
   reads **OVER**. This is the *expectation* layer: it says whether a rate is
   normal **for that actor**, not just whether the lane is loaded. (Bands are
   served by the portal registry; the local fabric runs no portal, so here we
   show the rate the band is computed from and explain the band — honestly
   marked. On a live fabric `goat top` renders the band directly.)

This scenario only **detects** — it does not cut. Scenario 04 does the cut.

```bash
bin/access-mgmt 03-detect-the-spammer
```
