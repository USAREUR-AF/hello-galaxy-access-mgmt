# Honesty matrix — live vs. represented

The most important doc in the repo. Every claim the scenarios make is graded, so
you always know what was *proven* against real infrastructure and what was
*stood in for*. The two headline operations — rotate and revoke — are entirely
live. The only represented pieces are the ones a laptop structurally cannot run,
or that need a component the self-contained fabric deliberately omits.

| Element | What runs in the demo | Grade |
|---|---|---|
| **Zenoh router + mTLS, default-deny ACL** | real `eclipse/zenoh:1.9.0` (SHA-pinned), the fleet image | **live** |
| **Fabric-health meter / gauge / footprint** | the *same* `goat-fabric-health` image deployed on production fabrics | **live** |
| **Pre-cut slot pool + per-slot ACL scoping** | real grants keyed on cert CN == anchor; a cross-slot write is really denied | **live** |
| **Rotate in place** (fresh leaf, same anchor) | real re-mint + cert swap; the actor really keeps publishing; router config byte-identical | **live** |
| **Revoke = slot reclaim → writes denied** | real ACL edit + router reload; a real observer sees nothing land after the cut | **live** |
| **Detection: health gauge + per-producer footprint** | real readings off the live meter under real flood load | **live** |
| **Mesh-first cut** (delete the NetBird peer) | a laptop has no WireGuard mesh — this is the production-authoritative half | **represented** |
| **Throughput-envelope band** via the portal registry | the self-contained fabric runs no portal; the **rate is live**, the band is computed from it and the registry is represented | **represented** |
| **Automatic detector→revoke loop / relay rate-cap** | designed, not built — here a human operator makes the call | **represented** |

## Why the represented pieces are represented (not faked)

- **The mesh.** A browser or laptop cannot perform a WireGuard handshake, and
  there is no mesh on a self-contained box. Representing the mesh-first cut is
  honest by construction — there is no "you reached this far, therefore you're
  enrolled" sleight of hand. The half we *can* run for real (the slot reclaim)
  we do run, and it genuinely denies the writes.

- **The throughput-envelope band.** `goat top` renders an actor's band
  (LOW/normal/HIGH/**OVER**) by fetching the declared `{min,mean,high,max}`
  envelope from the portal registry. The self-contained fabric is a router + a
  meter, no portal — so the *expectation* side is represented while the *measured
  rate* side is fully live. A clean upgrade (a tiny static portal serving the
  envelopes so `goat top` renders the band live) is noted in `FINDINGS.md` and
  doesn't change the rotate/revoke arcs.

- **The automatic loop.** A no-human-in-the-loop detector→revoke and the relay's
  automatic per-peer rate cap are designed in goat, not yet built.
  Here the operator makes the cut decision; the *machinery* of the cut is real
  and instant. That's the honest sandbox posture: a human decides, the fabric
  makes the decision land.

## The discipline

If a future change to this repo makes a represented thing *look* live without
making it live, that is a regression — the same bar goat holds itself
to (the fabric-health "never a false green" rule). When in doubt, grade down and
say so.
