#!/usr/bin/env bash
# Scenario 04 — Revoke a flooding actor: cut, deny, recover.
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib/access-mgmt.sh"
am_parse_env "$@"; set -- "${AM_ARGS[@]}"

am_banner "Revoke the spammer — reclaim its slot, deny its writes, recover" \
          "Mesh-first revocation: the cut lands in seconds."

am_preflight || exit 1

if ! am_is_local; then
  am_step "On a live fabric: the standing enforcement behind the cut"
  am_say "The cut's teeth are an identity-bound write-ACL. We can prove that floor"
  am_say "is live: a write your identity isn't authorised for is denied."
  am_step "The production cut commands (a real backend admin runs these for real)"
  am_say "Fast emergency cut of a flooder (mesh-first — deletes its NetBird peer,"
  am_say "tunnel drops; the pre-baked slot ACL can't stop it, removing the peer does):"
  printf '      %sgoat admin peer cut <peer> --context %s%s\n' "$C_BOLD" "$AM_ENV" "$C_RESET"
  am_say "Full offboarding when it's leaving for good (peer + identity + slot grant):"
  printf '      %sgoat admin onboard <handle> --revoke --context %s%s\n' "$C_BOLD" "$AM_ENV" "$C_RESET"
  am_say "Both are admin-gated server-side. See docs/do-it-for-real.md."
  am_honest "the full flood → cut → recover arc runs in --env local (it needs control"
  am_honest "of the router). Re-run:  bin/access-mgmt 04-revoke-the-spammer --env local"
  exit 0
fi

LOUD="$(am_anchor loud-mouth)"
FLOOD_KEY="$LOUD/sensor/flood"

am_step "1 — Recap: loud-mouth floods, the gauge goes red"
am_cmd "goat mock $FLOOD_KEY --rate 450   (background)"
am_start_load loud-mouth "$FLOOD_KEY" 450 10000 >/dev/null
sleep 12
FLOODED="$(am_goat health 2>/dev/null)"; printf '%s\n' "$FLOODED" | sed 's/^/    /'
FLOOD_OVERALL="$(am_overall "$FLOODED")"
FOOT="$(am_goat health --peer "$LOUD" 2>/dev/null)"
printf '%s\n' "$FOOT" | sed -n '/footprint/,$p' | sed 's/^/    /'

am_step "2 — The operator decides: this producer is the offender. Cut it."
am_say "Rank #1, near-limit, owning the lane (scenario 03). Revoke it."

am_step "3 — REVOKE: mesh-first cut + reclaim the slot from the ACL"
am_cmd "goat admin peer cut loud-mouth   (prod; here: local-fabric/revoke.sh reclaims the slot)"
am_say "(prod's authoritative half is the mesh peer cut — represented locally;"
am_say " the slot reclaim is the half we run for real on the laptop)"
bash "$AM_FAB/revoke.sh" revoke | sed 's/^/    /'

am_step "4 — Verify the offender is now DENIED"
am_say "It keeps trying to publish across the cut; a real observer sees nothing land:"
SEEN="$(am_count_after_cut loud-mouth "$LOUD")"; SEEN="${SEEN:-0}"
am_note "samples the observer saw from the offender AFTER the cut: $SEEN"

am_step "5 — Recover: the gauge returns to calm"
sleep 6
RECOVERED="$(am_goat health 2>/dev/null)"; printf '%s\n' "$RECOVERED" | sed 's/^/    /'
REC_OVERALL="$(am_overall "$RECOVERED")"
REC_C2="$(am_class_rate "$RECOVERED" C2)"; REC_C2="${REC_C2:-0}"

am_step "Restore the slot (so this scenario is repeatable)"
bash "$AM_FAB/revoke.sh" restore >/dev/null 2>&1
am_say "slot returned to the pool — loud-mouth could be re-issued, or left cut."

am_step "Verify the whole arc"
am_assert "the flood drove the gauge off GREEN (AMBER/RED)" \
  bash -c "[ '$FLOOD_OVERALL' = 'AMBER' ] || [ '$FLOOD_OVERALL' = 'RED' ]"
am_assert "the cut DENIED the offender's writes (observer saw nothing)" \
  test "$SEEN" -eq 0
am_assert "the situational lane recovered (C2 load fell back)" \
  awk "BEGIN{exit !($REC_C2 < 50)}"
am_assert "the gauge is no longer RED" bash -c "[ '$REC_OVERALL' != 'RED' ]"

am_honest "an AUTOMATIC detector→revoke (no human) and the relay's automatic per-peer"
am_honest "rate-cap are designed, not built — here the operator makes the call."

echo
am_say "That's the lifecycle: pre-cut slots → rotate in place → detect → revoke."
am_summary
