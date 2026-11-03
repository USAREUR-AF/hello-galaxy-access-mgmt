# The slot pool — the engineering that makes rotate & revoke dynamic

**This is the most important scenario in the repo.** It shows the mechanism that
everything else relies on.

## The problem it solves

The goat fabric is **brokerless**: a Zenoh router moves messages peer-to-peer
with no central message broker. That is a deliberate scaling and resilience win,
but it has a consequence — the router's access-control list (ACL) is **static**.
It is read at startup and cannot be safely hot-edited per tenant while the router
is serving live traffic. So how do
you *dynamically* manage who can write — rotate one identity, revoke another —
without restarting the world every time?

## The answer: pre-cut the slots

You don't make the ACL dynamic. You **pre-cut a pool of identity slots into it up
front**:

- Each slot is a fixed **32-hex anchor** (a UUID-shaped write identity).
- For each slot, a write grant for `<anchor>/**` is baked into the static ACL,
  keyed on the certificate **Common Name** being equal to that anchor.
- The grant follows the **slot**, never a particular leaf certificate.

That single decision is what makes both lifecycle operations cheap:

| Operation | What moves | What the router does |
|---|---|---|
| **Rotate** | a fresh leaf cert for the **same** anchor | **nothing** — the grant keys on the anchor, which didn't move. No re-render, no reload. |
| **Revoke** | the slot's grant is removed (+ mesh cut) | reload once; the slot returns to the pool, ready to re-issue |
| **Onboard** | hand someone the cert for a **free** slot | nothing — the grant was already pre-cut |

This is the local, runnable version of the slot-pool design (ADR 1025) and the
in-place rotation (ADR 1044) and mesh-first revocation (ADR 1031) in
[goatcore](https://github.com/usareur-af/goatcore) `docs/adr/`.

## What this scenario proves

1. The ACL really is keyed on the anchor (you'll see the actual router rules).
2. A leaf may write **only its own** slot — writing another slot's namespace is
   silently denied (default-deny). The grant is per-slot, not "any valid cert."
3. There is a **free** slot: authorised in the ACL with no leaf minted yet —
   onboarding a new actor is just minting a leaf for it.

```bash
bin/access-mgmt 01-the-slot-pool
```
