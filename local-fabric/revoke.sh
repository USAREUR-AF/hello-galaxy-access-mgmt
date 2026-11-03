#!/usr/bin/env bash
# revoke.sh — revoke the spamming actor by RECLAIMING ITS SLOT.
#
# This is the local-fabric realisation of mesh-first revocation (ADR 1031).
# Production revocation has two halves:
#   1. mesh-first (authoritative, instant): delete the offender's NetBird peer,
#      so its WireGuard tunnel drops and it has no path to the router at all.
#      There is no mesh on a laptop, so this half is REPRESENTED, not run.
#   2. slot reclaim (defence-in-depth, applied here LIVE): remove the slot's
#      write grant from the router ACL and reload. The reclaimed slot returns to
#      the pool, ready to re-issue. This is the Zenoh-layer half, and it is real.
#
# Because the grant keys on the slot anchor, removing one slot denies every leaf
# under it at once — no per-leaf bookkeeping, no CRL (ADR 0407).
#
# usage:  revoke.sh revoke   # reclaim the loud-mouth slot (deny its writes)
#         revoke.sh restore  # return the slot to the pool (repeatable demo)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib-fabric.sh"
DC="docker compose"; docker compose version >/dev/null 2>&1 || DC="docker-compose"

mode="${1:-revoke}"
case "$mode" in
  revoke)  echo "==> reclaiming the loud-mouth slot ($FAB_ANCHOR_LOUD) from the ACL"
           render_router_config revoke > "$FAB_STATE/router.json5" ;;
  restore) echo "==> re-granting the loud-mouth slot ($FAB_ANCHOR_LOUD)"
           render_router_config full   > "$FAB_STATE/router.json5" ;;
  *) echo "usage: revoke.sh revoke|restore" >&2; exit 2 ;;
esac

# Reload the router so the new ACL takes effect. (zenohd reads config at start;
# a container restart applies it cleanly — the meter + peers reconnect.)
( cd "$HERE" && $DC restart zenoh-router >/dev/null 2>&1 )

# Wait for the router to accept connections + the meter to resume publishing.
for _ in $(seq 1 20); do
  if goat --profile-dir "$HERE/profiles/operator" health 2>/dev/null | grep -q "FABRIC:"; then break; fi
  sleep 2
done
echo "router reloaded ($mode)"
