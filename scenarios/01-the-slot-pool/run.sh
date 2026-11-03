#!/usr/bin/env bash
# Scenario 01 — The slot pool: the engineering under rotate & revoke.
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib/access-mgmt.sh"
am_parse_env "$@"; set -- "${AM_ARGS[@]}"

am_banner "The slot pool — what makes dynamic access management possible" \
          "Static router ACL + pre-cut slots = rotate and revoke without a rebuild."

am_preflight || exit 1

if ! am_is_local; then
  am_say "This scenario inspects the local router's rendered ACL, so it needs"
  am_say "control of the router. Re-run with:  bin/access-mgmt 01-the-slot-pool --env local"
  exit 0
fi

WEATHER="$(am_anchor weather-vane)"
STEADY="$(am_anchor steady-eddie)"

am_step "1 — The pre-cut pool"
am_pool | awk -F'\t' '{printf "  • %-13s %s  %s\n",$1,$2,$3}'
am_say "Three slots are ALLOCATED to actors; one is FREE — pre-cut into the ACL"
am_say "but with no leaf minted. Onboarding = handing someone that free slot's cert."

am_step "2 — The ACL is keyed on the slot anchor, not the leaf"
am_say "Here are the live router's per-slot write grants (rendered config):"
grep -E '"(w|s)-(weather|steady|loud|free)"' "$AM_FAB/.state/router.json5" \
  | sed -E 's/^ */    /'
am_say "Each 'w-<slot>' rule allows writes to <anchor>/** ; each 's-<slot>' subject"
am_say "matches a leaf whose CN == that anchor. The grant is bound to the SLOT."

am_step "3 — A leaf may write only its OWN slot (default-deny everywhere else)"
am_say "weather-vane writes its own anchor — admitted + routed to a real observer:"
if am_observe_publish weather-vane "$WEATHER/sensor/temp" "own-slot-$$"; then
  am_ok "weather-vane → its own slot: ADMITTED (observer saw it)"
else
  am_fail "weather-vane could not write its own slot"
fi
am_say "Now weather-vane tries to write steady-eddie's anchor — not its slot:"
if am_observe_publish weather-vane "$STEADY/sensor/spoof" "cross-slot-$$"; then
  am_fail "cross-slot write was ADMITTED — the ACL is not slot-scoped!"
  X_DENIED=1; X_DENIED=0
else
  am_ok "weather-vane → steady-eddie's slot: DENIED (observer saw nothing)"
  X_DENIED=1
fi

am_step "4 — Why this makes rotate & revoke trivial"
am_say "Because authority lives on the SLOT:"
am_note "ROTATE: a fresh leaf with the same CN is admitted by the same rule —"
am_note "        no ACL change, no router reload.  (scenario 02 proves it)"
am_note "REVOKE: drop the slot's rule + reload, and every leaf under it is denied"
am_note "        at once — no per-leaf bookkeeping, no CRL.  (scenario 04 proves it)"

am_step "Verify"
am_assert "weather-vane can write its own slot" test "${AM_OBS_SEEN:-0}" -ge 0
am_assert "a cross-slot write is denied (per-slot scoping holds)" test "${X_DENIED:-0}" -eq 1
am_assert "the free slot is authorised in the ACL with no leaf minted" \
  bash -c "grep -q 's-free' '$AM_FAB/.state/router.json5' && [ ! -f '$AM_FAB/zenoh/tls/$(am_anchor '(free)')-cert.pem' ]"

echo
am_say "Next: bin/access-mgmt 02-rotate-live-actor"
am_summary
