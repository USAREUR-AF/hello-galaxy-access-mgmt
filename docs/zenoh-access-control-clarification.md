# Zenoh access control: the static-ACL revocation misconception

A common conclusion about Zenoh access control that is wrong in one specific,
consequential way. This documents what's actually true, why the wrong version is
easy to land on, and the code/scenarios that prove it.

## The claim

> *"Zenoh has no dynamic ACL. Slots are allocated at server initialization; set
> an arbitrarily large number. Regional ACLs are evaluated and rejected, which
> means revoking one bad actor would require revoking the entire region. The
> longer-term option: fork Zenoh and build more robust native access control."*

## TL;DR

- **Right:** Zenoh's ACL is static (read at startup). Slots are pre-allocated at
  init, pool sized large. Both correct.
- **Wrong:** "revoking one bad actor requires revoking the entire region." Slots
  are **per-identity, disjoint grants** — revoking one removes one slot's rule and
  denies that actor alone.
- **Therefore:** no Zenoh fork is needed for access control. Per-identity rotate
  and revoke work today on the stock router.

The "revoke the whole group" behaviour is real, but only for the **legacy
shared-certificate model** (one cert per vendor org), which the per-uuid slot
model replaces.

## Where the wrong version comes from

It's the conclusion you reach from the **problem** without the **response**. The
limitation is documented loudly in one place; the design that resolves it is one
layer deeper. Specific path:

1. Search "does Zenoh do dynamic ACL / how do we revoke" → hit the true,
   prominent statement: the ACL is static, not hot-editable per tenant
   (goat's brokerless design notes: "no dynamic ACL").
2. Also pick up the real provisioning shape: slots allocated at init, count set
   large. Correct.
3. Grants are key-expression rules and can look **coarse** at a glance. Combine
   with the still-present **legacy shared-cert model** (whole org shares one
   identity) and you get "a grant covers a group → revoke one = revoke the group."
4. "Static ACL + group-shaped grants + can't edit live" → "fork Zenoh for real
   per-identity authz."

The analysis stopped at the static-ACL limitation and the shared-cert model and
didn't reach ADR 1025 (per-uuid slot pool) or ADR 1031 (mesh-first revoke).

## What's correct

- **"No dynamic ACL."** ✅ The router reads access-control config at startup; we
  don't hot-edit per-tenant rules into a live router.
- **"Slots allocated at init; set a large number."** ✅ The right design. Slots
  are cheap (a few lines of config each), so the pool is pre-provisioned large.

## What's wrong: slots are per-identity, not regional

The slots are **not** a shared regional grant. Each slot is a distinct identity —
a unique 32-hex anchor with its **own** write grant, keyed on a cert whose Common
Name equals that anchor. One actor → one slot → one grant. Disjoint by
construction.

Revoking one actor = removing **one** slot's subject+policy. It denies every leaf
that ever presented that anchor (so a rotated-but-compromised key dies with it)
and **nothing else**. No region comes down with it. No CRL to distribute —
reclaiming the slot *is* the authorization cut. That's the entire point of cutting
the pool into per-identity slots up front: per-individual revocation on a static
ACL without editing it live.

The "whole region" reading is a correct reading of the **wrong (legacy) model** —
one shared cert per vendor org, where revoking the shared identity cuts everyone
under it (the "last-one-out" rule). Per-uuid slots dissolve exactly that. If the
analysis was looking at shared-cert grants, the conclusion followed; the model was
the problem, not the logic.

### "Regional ACLs are evaluated and rejected"

That's default-deny working **per write, per identity** — every write is checked
against the per-identity grants and rejected if none match. It's the fine-grained
gate, not a coarse regional one. (Reads are mostly permissive; *writes* are scoped
per anchor.)

## No fork needed

Per-identity rotate and revoke already work on the stock router via two layers:

1. **Mesh-first cut (authoritative, instant).** Revocation deletes the actor's
   network peer (NetBird/WireGuard); the tunnel drops, no path to the router. A
   cert is inert without a route. The dynamic, instant cut lives at the network
   admission layer — which *is* dynamic.
2. **Slot reclaim (defence-in-depth).** Remove that one slot's grant and reload —
   scoped to that slot.

Forking the router for "dynamic native authz" re-introduces the central, stateful
component the brokerless design removed, and buys nothing here. We do keep reasons
to own the router build — shared-memory transport, router stats — but per-tenant
authorization is not one of them.

## Corrected version

> Zenoh's ACL is static, so we don't edit it live. We pre-cut a large pool of
> per-identity slots into it at init, each slot its own anchor and grant. Rotating
> an actor re-keys its slot in place with zero router change; revoking one removes
> that single slot (plus the authoritative mesh-first peer cut) and denies that
> actor alone, never a region. The "revoke the whole group" case applies only to
> the legacy shared-cert model that per-slot identities replace. No Zenoh fork is
> needed for access control.

## It runs

This repo proves each point against a real Zenoh router:

- [`scenarios/01-the-slot-pool`](../scenarios/01-the-slot-pool) — shows the actual
  per-slot grants; a cross-slot write is denied. Slots are disjoint, not regional.
- [`scenarios/02-rotate-live-actor`](../scenarios/02-rotate-live-actor) — rotates
  one actor; router config is byte-identical (zero reloads); it keeps publishing.
- [`scenarios/04-revoke-the-spammer`](../scenarios/04-revoke-the-spammer) — revokes
  one actor by reclaiming one slot; its writes are denied, neighbours untouched.

## Pointers (goatcore)

- **ADR 1025** — Zenoh dynamic tenant authz via a pre-cut slot pool (the response).
- **ADR 1031** — mesh-first credential revocation & offboarding.
- **ADR 1044** — in-place credential rotation.
- `docs/design/zenoh-brokerless-consequences.md` — why not to re-add a central component / fork
  for authz, and what owning the router build is actually for.
- [`the-slot-pool.md`](the-slot-pool.md) — the mechanism in full.
