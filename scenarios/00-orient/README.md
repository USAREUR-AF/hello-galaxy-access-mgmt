# Orient — the goatnet, the slot pool, and what we're about to do

This series shows two everyday access-management operations on the goat data
fabric, run for real against a tiny local fabric:

1. **Rotate** a *live* actor's credential — refresh its certificate without it
   ever losing its identity or stopping work.
2. **Detect and revoke** a *misbehaving* actor — spot a producer flooding the
   fabric and cut its write access in seconds.

Both are made cheap and dynamic by one piece of engineering under the surface:
the **pre-cut UUID slot pool**. The next scenario (`01-the-slot-pool`) is all
about that mechanism — read it before the lifecycle ones; it is what makes the
rest possible.

This orient step just confirms the fabric is up and shows you the slot pool and
the health gauge you'll watch throughout.

Run it:

```bash
local-fabric/up.sh                     # once, to start the fabric
bin/access-mgmt 00-orient
```
