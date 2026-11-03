#!/usr/bin/env bash
# Scenario 00 — Orient.
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib/access-mgmt.sh"
am_parse_env "$@"; set -- "${AM_ARGS[@]}"

am_banner "Orient — the slot pool + the health gauge" \
          "Two operations ahead: rotate a live actor, and revoke a flooding one."

am_preflight || exit 1

am_step "The pre-cut slot pool"
am_say "Every actor on the fabric holds a SLOT — a fixed 32-hex anchor that is its"
am_say "write identity. The router's ACL grants writes per slot, pre-cut up front."
am_pool | awk -F'\t' '{printf "  • %-13s %s  %s\n",$1,$2,$3}'

am_step "The health gauge"
am_say "The same goat-fabric-health meter that runs on production fabrics watches"
am_say "this one. Right now it should be calm (idle/green — no real load yet)."
if am_is_local; then
  am_goat health 2>/dev/null | sed 's/^/    /'
else
  am_goat health 2>/dev/null | sed 's/^/    /'
fi

am_step "What's next"
am_note "01-the-slot-pool       — the engineering that makes rotate/revoke dynamic"
am_note "02-rotate-live-actor   — refresh a credential with zero downtime"
am_note "03-detect-the-spammer  — spot a flooder on the gauge + footprints"
am_note "04-revoke-the-spammer  — cut its access in seconds, watch recovery"

echo
am_say "Run them in order, or 'bin/access-mgmt all'."
