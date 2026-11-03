# Rotate a live actor — refresh its credential with zero downtime

A certificate expires, or you want to re-key after a scare. On most systems that
means re-provisioning the identity: new name, new address, consumers reconfigured,
stored data orphaned. On goat it means **none of that** — you rotate the leaf
*in place*.

## What you'll see

`weather-vane` is a live sensor publishing on its slot. We:

1. Watch it publish (an observer sees its samples land).
2. **Rotate** it — `goat admin rotate weather-vane` in production; here
   `local-fabric/rotate.sh`. A fresh leaf certificate is minted for the **same
   slot anchor** and swapped onto the actor.
3. Watch it publish again — on the **new** leaf, to the **same** namespace, seen
   by the same observer.

And we prove the three things that make this safe and cheap:

- the leaf genuinely changed (new key, new serial, new fingerprint),
- the **anchor did not move** (same write namespace, same identity), and
- the **router config is byte-for-byte identical** before and after — the ACL
  was never touched, the router never reloaded.

That last point is the slot pool paying off: because the grant keys on the
anchor (scenario 01), a rotated credential is admitted by the unchanged rule.

## Honest caveat

Rotation does **not** cryptographically kill the old leaf — goat ships no
CRL/OCSP by design. The old cert stays valid until it expires. When the old key
must die *now* (compromise), you compose rotation with the mesh-first cut from
scenario 04 (delete the peer; a cert is inert with no network path).

```bash
bin/access-mgmt 02-rotate-live-actor
```
