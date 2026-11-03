# The pre-cut UUID slot pool — the engineering under the surface

This is the one mechanism the whole repo rests on. Understand this and both
rotation and revocation become obvious.

## The constraint we design around

The goat fabric is **brokerless**: a Zenoh router moves messages peer-to-peer
with no central message broker in the data path. That is a deliberate choice — a
central broker would be a single point of failure and a hard ceiling on
throughput. But it has a direct consequence for access control:

> The router's access-control list (ACL) is **static**. It is read at startup and
> is not safely hot-editable, per tenant, while the router is serving live
> traffic.

That's a real limitation of the stock router.
Taken alone, it *sounds* like it forces a grim trade-off: if you can't edit the
ACL live, then surely you can't grant or revoke individual identities without
restarting the world, or you must group identities coarsely and accept collateral
cuts. **Both of those conclusions are wrong**, and the reason is the slot pool.

## The move: pre-cut the slots instead of editing live

You don't make the ACL dynamic. You **pre-cut a pool of identity slots into the
static ACL up front**:

- Each slot is a fixed **32-hex anchor** — a UUID-shaped write identity.
- For each slot, a write grant for `<anchor>/**` is baked into the static ACL,
  **keyed on the certificate Common Name being equal to that anchor**.
- The grant follows the **slot**, never a particular leaf certificate.

You provision the pool generously (a large number of slots) at initialization,
because slots are cheap — each is just a few lines of ACL. Allocating an actor to
a slot, or freeing one, never re-opens the router config in a way that disturbs
live traffic.

In this repo the pool is rendered by
[`local-fabric/lib-fabric.sh`](../local-fabric/lib-fabric.sh); here's the shape of
a single slot's grant:

```json5
rules:    [ { id: "w-weather", messages: ["put","delete"], flows: ["ingress"],
             permission: "allow", key_exprs: ["a11ce551…/**", "volatile/a11ce551…/**"] } ],
subjects: [ { id: "s-weather", cert_common_names: ["a11ce551…"] } ],
policies: [ { rules: ["w-weather"], subjects: ["s-weather"] } ]
```

The grant (`w-weather`) is tied to the subject (`s-weather`), which matches **any
leaf whose CN equals the anchor**. The leaf is interchangeable; the slot is the
identity.

## Why this makes the lifecycle operations trivial

| Operation | What actually changes | What the router does |
|---|---|---|
| **Onboard** | hand a participant the certificate for a **free** (pre-cut, unheld) slot | **nothing** — the grant was already there |
| **Rotate** | mint a fresh leaf with the **same CN/anchor**, swap it on the peer | **nothing** — the unchanged grant admits the new leaf; no re-render, no reload |
| **Revoke** | remove **one** slot's subject+policy and reload (+ the mesh-first cut) | one reload; the slot returns to the pool, deny is **scoped to that slot alone** |

The revoke row is the crux: because each actor has its **own** slot anchor with
its **own** grant, revoking one actor removes exactly one slot's rule. It denies
every leaf that ever presented that anchor at once (so a rotated-but-compromised
key dies with it) **and nothing else** — no neighbour, no "region," no shared
group is affected. There is no certificate revocation list to distribute and
consult (goat ships none by design); reclaiming the slot *is* the authorization
cut.

## Where the dynamic cut-off really lives

"Static ACL" does **not** mean "no dynamic access management." It means the
*dynamic* decisions are layered correctly:

- **Network admission** (NetBird/WireGuard) — the authoritative, instant cut. A
  deleted peer has no path to the router at all; a certificate is inert without a
  network route. This is why production revocation is **mesh-first**.
- **The slot reclaim** at the static ACL — defence-in-depth, scoped to one slot.
- **Identity/role** (Ory) — who may *perform* a rotate or revoke.

The router's static ACL is the **write-integrity** layer, not the place dynamic
per-principal cut-off is attempted. Each layer does the job it's best at, and
together they give live, per-identity access management on a brokerless fabric.

## What this is NOT, and why no fork is needed

It is tempting to conclude "we must fork Zenoh and build richer native access
control to revoke individuals." You don't. Forking the router for *authorization*
would re-introduce exactly the central, stateful component the brokerless design
removed — and it's unnecessary, because the pre-cut slot pool plus mesh-first cut
already give per-identity rotate and revoke today. (Forking the router image is
reserved for genuinely different needs — shared-memory transport, router stats —
not for this.) The longer discussion of this exact misunderstanding is in
[`zenoh-access-control-clarification.md`](zenoh-access-control-clarification.md).

## See it run

- [`scenarios/01-the-slot-pool`](../scenarios/01-the-slot-pool) — proves a leaf
  may write only its own slot (cross-slot writes are denied).
- [`scenarios/02-rotate-live-actor`](../scenarios/02-rotate-live-actor) — proves a
  rotation changes the leaf but **not** the router config (zero reloads).
- [`scenarios/04-revoke-the-spammer`](../scenarios/04-revoke-the-spammer) — proves
  reclaiming one slot denies that actor alone.

## Design records (goatcore `docs/adr/`)

- ADR 1025 — Zenoh dynamic tenant authz via a slot pool
- ADR 1031 — mesh-first credential revocation & offboarding
- ADR 1044 — in-place credential rotation
- `docs/design/zenoh-brokerless-consequences.md` — why not to re-introduce a broker/fork
