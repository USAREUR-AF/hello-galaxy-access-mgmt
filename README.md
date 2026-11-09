# hello-galaxy-access-mgmt

**A hands-on demonstration of how the goat data fabric manages identities over
their lifetime — rotating a live actor's credential with zero downtime, and
detecting & revoking a misbehaving one in seconds — that you can run yourself in
a few minutes.**

This repo is a *series of small, self-contained scenarios*. Each one is a short,
cold-readable runbook plus a single script that drives the real `goat`
command-line tool against a **real** Zenoh router and the **real** production
fabric-health meter, narrating what happens as it happens. You do not need to
understand the fabric's internals to follow along.

The whole point: **show, don't tell.** Where a capability is real and live, the
scenario proves it. Where something can't run on a laptop (a WireGuard mesh) or
needs a component this sandbox omits (the portal), the scenario says so plainly
and never fakes it — see [the honesty matrix](docs/honesty-matrix.md).

---

## What you'll learn, in one picture

Two everyday operations, and the one piece of engineering that makes both cheap:

| Operation | Plain meaning | What the demo shows |
|---|---|---|
| 🔄 **Rotate** | refresh an actor's certificate without it losing its identity or stopping work | publish → rotate → still publishing, on a fresh leaf, **zero router reloads** |
| 🚨 **Detect** | spot a flooder and be sure *which identity* it is | the health gauge + per-producer footprint + throughput-envelope band |
| ✂️ **Revoke** | cut a bad actor's write access in seconds | reclaim its slot → its writes are denied → the fabric recovers |

**Under the surface, the enabler is a pre-cut UUID slot pool.** The Zenoh router's
access-control list is *static* (read at startup, no central broker by design). So
instead of making the ACL dynamic, goat **pre-cuts a pool of identity slots** into
it: each slot is a fixed anchor whose write grant keys on the certificate, and the
grant follows the **slot**, not the leaf. That is what lets you rotate one identity
(same slot → no ACL change) and revoke another (drop one slot → deny it alone,
*not* the whole region). Scenario [`01-the-slot-pool`](scenarios/01-the-slot-pool)
is dedicated to this mechanism — read it first.

---

## Quick start

### Prerequisites

- **Docker** (for the self-contained local fabric)
- **`goat`** CLI on your `PATH` — the goat operator binary, built from
  [goatcore](https://github.com/usareur-af/goatcore)
  (`cd crates && cargo build --release -p goat-cli`)
- **openssl** (mints the throwaway demo certificates)

### Run it

**No goatnet account and no fabric identity needed.** The local fabric is fully
self-contained: `up.sh` mints its own throwaway CA and a leaf cert per slot, so
the entire rotate + detect + revoke arc runs with nobody cutting you anything.
Both images (`eclipse/zenoh` and `ghcr.io/usareur-af/goat-fabric-health`) are
public and pinned by digest.

```bash
# 1. bring up the self-contained fabric (real zenohd + real health meter)
#    — gen-certs.sh mints a disposable CA + per-slot leaves; nothing external needed
local-fabric/up.sh

# 2. walk the scenarios in order
bin/access-mgmt 00-orient
bin/access-mgmt 01-the-slot-pool        # the engineering under the surface — read first
bin/access-mgmt 02-rotate-live-actor    # refresh a credential with zero downtime
bin/access-mgmt 03-detect-the-spammer   # three honest detection signals
bin/access-mgmt 04-revoke-the-spammer   # cut its access, watch recovery

# …or run them all, and generate the report
bin/access-mgmt all --env local
report/generate-report.sh               # → report/report.html

# 3. tear it all down (wipes the throwaway certs + state)
local-fabric/down.sh
```

Every scenario *also* accepts `--env <goat-context>` to point at a live goatnet
you have access to:
a goatlite you stand up yourself (goatcore's goatlite quickstart,
`docs/tutorials/00-goatlite.md`); or another goatnet you have access to. That's
the **only** mode that needs an
operator-issued cert in your `goat` profile, and it is deliberately **read-only**:
it shows the production command and proves the standing ACL floor is live, without
mutating anything. The full rotate/revoke arc runs only in `--env local`, against
the disposable fabric.

**If you are a backend admin** with operator credentials on a live goatnet, you
can do all of this *for real* — the production commands (`goat admin rotate`,
`goat admin peer cut`, `goat admin onboard --revoke`) are admin-gated server-side,
so they execute for an admin and are denied for everyone else. The runbook is
[`docs/do-it-for-real.md`](docs/do-it-for-real.md).

---

## The report

[`report/generate-report.sh`](report/generate-report.sh) runs every scenario
against the live local fabric, captures the **real** output and metrics, and
emits a self-contained, styled **`report/report.html`** with figures (the slot
pool, the rotate timeline, the detect→revoke flow), the captured terminal output,
a verdict table, and the honesty matrix. Nothing in it is faked — re-run it and
every number is read back fresh from a live run.

---

## Repo layout

```
bin/access-mgmt            dispatcher: bin/access-mgmt <scenario> [--env ...]
lib/access-mgmt.sh         shared scenario library (goat wrapper, narration, asserts)
local-fabric/
  lib-fabric.sh            ← the pre-cut SLOT POOL + the router ACL it renders (the core)
  gen-certs.sh             mint a throwaway CA + one leaf per slot
  docker-compose.yml       real zenohd + real goat-fabric-health meter (demo-scaled)
  up.sh / down.sh          bring the fabric up / wipe it
  rotate.sh                re-mint a leaf for the SAME slot anchor (rotation in place)
  revoke.sh                reclaim a slot from the ACL (the Zenoh half of a mesh-first cut)
scenarios/                 00-orient … 04-revoke-the-spammer (README + run.sh each)
report/                    generate-report.sh + figures/ → report.html
docs/                      00-what-is-access-mgmt · the-slot-pool · honesty-matrix · do-it-for-real
                           · zenoh-access-control-clarification
FINDINGS.md                what didn't work first try, and how it was fixed
```

---

## How this maps to production goat

| Here (local) | Production goat | Design record (goatcore `docs/adr/`) |
|---|---|---|
| `local-fabric/rotate.sh` | `goat admin rotate <anchor\|alias>` | ADR 1044 — in-place credential rotation |
| `local-fabric/revoke.sh` (flooder cut) | `goat admin peer cut <peer>` (emergency, mesh-first) | ADR 1031 — mesh-first revocation |
| `local-fabric/revoke.sh` (full offboard) | `goat admin onboard <handle> --revoke` | ADR 1031 — mesh-first revocation |
| pre-cut slot ACL in `lib-fabric.sh` | the slot-pool write-anchor ACL | ADR 1025 — dynamic tenant authz |
| `goat health` gauge + footprint | the same meter image | ADR 1034 — fabric-health surface |
| envelope band (represented) | `goat top` band | ADR 1045 — throughput envelopes |

Part of the **hello-galaxy** family of runnable goat demos (universal-id,
zenoh-patterns, spire-spiffe-patterns).

## Licence

`hello-galaxy-access-mgmt` was written by U.S. Federal government employees. In the U.S. it is not subject to copyright and is in the public domain; in countries where copyright is recognized, it is released under the [Apache License 2.0](LICENSE). See [INTENT.md](INTENT.md).
