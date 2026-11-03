# What is access management on the goat fabric?

A short, plain-language orientation. No prior fabric knowledge assumed.

## The setting

The goat fabric is a mesh that carries data between many participants — sensors,
services, operators, partner units. Each participant has an **identity** (a
certificate) and is allowed to **write** only to its own slice of the namespace.
Identities don't live forever: certificates expire, get re-keyed after a scare,
and sometimes a participant misbehaves and has to be cut off. Managing those
changes safely and quickly is **access management**.

Two operations cover most of the day-to-day:

- **Rotation** — give an existing, trusted participant a *fresh* credential
  without changing who it is or interrupting its work. (Renewal, re-keying.)
- **Revocation** — take a participant *off* the fabric. (Departure, compromise,
  or a flooder that has to be stopped.)

This repo demonstrates both, for real.

## Why it's usually hard — and why it isn't here

On most systems, changing a credential means re-provisioning the identity: a new
name, a new address, every consumer reconfigured, stored data orphaned. And
revoking one bad actor often means coarse, collateral cuts because the
authorization is grouped.

goat avoids both by binding authority to a **slot** — a fixed identity anchor —
rather than to a particular certificate or to a shared group. The certificate can
be swapped under the slot (rotation) without anything downstream noticing, and a
single slot can be reclaimed (revocation) without touching anyone else's. The
mechanism that makes this work is the **pre-cut slot pool** —
see [`the-slot-pool.md`](the-slot-pool.md).

## What "in seconds" means

- **Rotation** is effectively instant and causes **zero** disruption: the router
  isn't even reloaded, because the slot's grant didn't move.
- **Revocation** lands as fast as the cut is applied. In production the
  authoritative half is *mesh-first* — the offender's network peer is deleted and
  its tunnel drops immediately — and the slot is reclaimed from the router's ACL
  as defence-in-depth. From that instant its writes are denied.

## What this demo proves vs. represents

Everything that *can* run on a laptop runs for real: a real Zenoh router with a
real mTLS, default-deny ACL; the real production health meter; real certificate
minting, rotation, and ACL reclaim. The only represented pieces are the ones a
laptop structurally can't host — a WireGuard mesh — and one component the
self-contained fabric omits (the portal). Those are marked everywhere they
appear; the full accounting is in [`honesty-matrix.md`](honesty-matrix.md).
