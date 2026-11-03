# Do it for real — backend admin runbook

The scenarios run against the disposable local fabric so anyone can follow along
with no credentials. If you **are** a backend admin with operator credentials on a
goatnet of your own, here are the actual production commands to rotate and
revoke for real. They are the same operations the demo dramatizes — these are not
simulations.

## What you need (and why others can't run these)

- An **operator profile** — a `goat` context whose mTLS leaf was cut for you by an
  existing admin (`goat admin operator onboard <handle>`), carrying the operator
  Zenoh leaf + portal admin token scope.
- For the mesh cut: the NetBird admin token in your environment —
  `GOAT_NB_API_TOKEN`, or `<CONTEXT>_NB_API_TOKEN` for the context you target.

Every command below is **admin-gated server-side**: the portal checks your token
scope, NetBird checks the admin token. Without them the calls are denied — which
is why the demo's `--env <live>` mode is read-only for everyone, and why these
work only for an actual admin. The gate is real, not a README disclaimer.

Point `goat` at your goatnet with `--context <ctx>` (or `--env <ctx>` where a
command takes it). To build a goatnet, start from the goatlite quickstart in
[goatcore](https://github.com/usareur-af/goatcore) (`docs/tutorials/00-goatlite.md`).

---

## Rotate a credential for real

Re-key a peer in place — same anchor/alias/namespace/ACL, fresh leaf. For expiry
renewal, post-compromise re-key, or a URI-SAN retrofit.

```bash
# preview (resolves the alias→anchor, prints the intended request, mutates nothing)
goat admin rotate <anchor|alias> --context <ctx> --dry-run

# do it — prints a fresh one-time bundle URL
goat admin rotate <anchor|alias> --context <ctx>
```

Then on the peer: fetch the one-time bundle, swap `cert.pem` + `key.pem`, restart
the container. The anchor never moved, so the router ACL is untouched and nothing
else reconfigures.

Org-wide (every active member of an affiliation, in place):

```bash
goat admin rotate --org <affiliation-id> --context <ctx> --dry-run   # blast radius
goat admin rotate --org <affiliation-id> --context <ctx> --yes
```

**Compromise note:** rotation does not kill the old leaf (no CRL/OCSP by design).
If the old key must die *now*, compose with the mesh cut below — a cert is inert
without a mesh path.

---

## Detect a flooder for real

```bash
goat health --context <ctx>                      # the weather: which lane is hot
goat top --context <ctx> --once                  # per-producer ranking + envelope band
goat health --context <ctx> --peer <anchor>      # the offender's footprint
```

`goat top` renders the throughput-envelope **band** (LOW/normal/HIGH/**OVER**)
live against the portal registry — the part this repo's local fabric can only
represent.

---

## Revoke a flooder for real — two levers

### 1. Emergency cut (fast, authoritative): `goat admin peer cut`

On a brokerless slot-pool fabric the Zenoh write-ACL is pre-baked for the whole
pool, so **deleting a portal/vendor record does NOT stop a flooder** — removing
the *peer* does. A cert is inert without a mesh path. This is the one-command
emergency cut:

```bash
goat admin peer ls   --context <ctx>             # find the offender's peer
goat admin peer cut  <peer> --context <ctx>      # delete its NetBird peer → tunnel drops
```

Needs `<CONTEXT>_NB_API_TOKEN` (or `GOAT_NB_API_TOKEN`) in the environment. This is the live equivalent of the
demo's slot reclaim — except in production the *mesh* removal is the authoritative
half (the demo represents the mesh and reclaims the slot instead, because a laptop
has no mesh).

### 2. Full offboarding: `goat admin onboard --revoke`

When the actor is leaving for good (not just a flood to stop), run the complete
mesh-first offboarding — deletes the peer(s), deactivates the Ory identity,
reclaims the Zenoh grant — all from one command:

```bash
goat admin onboard <handle> --revoke --context <ctx> --dry-run   # preview the cuts
goat admin onboard <handle> --revoke --context <ctx>
```

Org-scope cascade (a whole unit):

```bash
goat admin onboard --org <affiliation-id> --revoke --context <ctx>          # prompts
goat admin onboard --org <affiliation-id> --revoke --context <ctx> --yes
```

Default revoke is reversible (Ory deactivate, not delete); add the playbook's
purge option for a terminal cut. Every revoke writes a receipt + audit row.

---

## Which to reach for

| Situation | Command |
|---|---|
| Cert expiring / re-key in place | `goat admin rotate <anchor\|alias>` |
| Flooder to stop *now* | `goat admin peer cut <peer>` |
| Participant leaving for good | `goat admin onboard <handle> --revoke` |
| A whole unit | `… --org <affiliation-id>` |

## Design records (goatcore `docs/adr/`)

- ADR 1044 — in-place credential rotation
- ADR 1031 — mesh-first credential revocation & offboarding
- ADR 1025 — Zenoh dynamic tenant authz via the slot pool
- goatcore `docs/operations/admin-operator-guide.md` — the full admin guide
