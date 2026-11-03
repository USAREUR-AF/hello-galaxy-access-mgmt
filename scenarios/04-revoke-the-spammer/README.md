# Revoke the spammer — cut its write access in seconds

You found the flooder (scenario 03) and you're sure. Now cut it off and watch the
fabric recover.

## How the cut works

Production revocation is **mesh-first** (ADR 1031) and has two halves:

1. **Mesh-first (authoritative, instant):** delete the offender's NetBird peer.
   Its WireGuard tunnel drops and it has no network path to the router at all.
   A laptop has no mesh, so this half is **represented** here, not run — but it is
   the half that does the real work in production.

2. **Slot reclaim (defence-in-depth, run here for real):** remove the offender's
   slot grant from the router ACL and reload. Because the grant keys on the slot
   anchor (scenario 01), removing one slot denies **every** leaf under it at once
   — no per-leaf bookkeeping, no certificate revocation list. The slot returns to
   the pool, ready to re-issue to someone trustworthy.

In production both run from one command: `goat admin onboard <handle> --revoke`.

## What you'll see

1. loud-mouth floods; the gauge goes red (the detection recap).
2. **Cut** — the slot is reclaimed from the ACL (`local-fabric/revoke.sh`).
3. The offender keeps trying to publish, but a real observer sees **nothing
   land** — its writes are denied from that instant.
4. The gauge **recovers** to calm.

## Honest caveat

An *automatic* detector→revoke loop (no human in the loop) and the relay's
automatic per-peer rate cap are designed, not built — here an operator makes the
call. That's the right default for a sandbox: a human decides, the machinery
makes the decision instant.

```bash
bin/access-mgmt 04-revoke-the-spammer
```
