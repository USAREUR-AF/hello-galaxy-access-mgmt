#!/usr/bin/env bash
# Scenario 03 — Detect a flooding actor (no cut yet).
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib/access-mgmt.sh"
am_parse_env "$@"; set -- "${AM_ARGS[@]}"

am_banner "Detect the spammer — gauge, footprint, envelope band" \
          "Find the flooder and be sure which identity it is — before cutting."

am_preflight || exit 1

if ! am_is_local; then
  am_step "On a live fabric: the detection surfaces are live right now"
  am_say "Read the gauge and the per-producer footprints on the real fabric:"
  am_cmd "goat health"
  am_goat health 2>/dev/null | sed 's/^/    /'
  am_cmd "goat top --once        # per-producer ranking + throughput-envelope band"
  am_honest "demo-scale load won't move a production-sized gauge; the full"
  am_honest "flood → detect → cut arc runs in --env local."
  exit 0
fi

LOUD="$(am_anchor loud-mouth)"
FLOOD_KEY="$LOUD/sensor/flood"

am_step "1 — Baseline: the gauge is calm"
am_goat health 2>/dev/null | sed 's/^/    /'

am_step "2 — loud-mouth starts flooding the situational lane"
am_note "offender slot: $LOUD"
am_cmd "goat mock $FLOOD_KEY --rate 450   (background)"
am_start_load loud-mouth "$FLOOD_KEY" 450 8000 >/dev/null
sleep 12

am_step "3 — Detection signal #1: the health gauge goes off green"
FLOODED="$(am_goat health 2>/dev/null)"; printf '%s\n' "$FLOODED" | sed 's/^/    /'
FLOOD_OVERALL="$(am_overall "$FLOODED")"

am_step "4 — Detection signal #2: the per-producer footprint names the culprit"
am_say "The gauge says the lane is hot; the footprint says WHO:"
FOOT="$(am_goat health --peer "$LOUD" 2>/dev/null)"
printf '%s\n' "$FOOT" | sed -n '/footprint/,$p' | sed 's/^/    /'
RANK1=0; printf '%s' "$FOOT" | grep -q 'rank #1' && RANK1=1
NEARLIMIT=0; printf '%s' "$FOOT" | grep -q 'near-limit' && NEARLIMIT=1

am_step "5 — Detection signal #3: the throughput-envelope band"
am_say "Each registered actor has a declared expected range {min,mean,high,max}."
am_say "loud-mouth's declared band (situational telemetry): max ≈ 50 msgs/s."
RATE="$(printf '%s' "$FOOT" | sed -n 's/.*— \([0-9]*\) msgs\/s.*/\1/p' | head -1)"; RATE="${RATE:-0}"
am_note "observed rate: ${RATE} msgs/s   vs declared max 50 msgs/s"
if [ "${RATE:-0}" -gt 50 ]; then
  am_warn "BAND = OVER  (${RATE} msgs/s ≫ max 50) — flooding past its declared ceiling"
fi
am_honest "the band is rendered live by 'goat top' against the portal envelope"
am_honest "registry; the local fabric runs no portal, so we compute it from the"
am_honest "footprint rate above. The rate + verdict are real; the registry is represented."

am_step "Verify the detection"
am_assert "the flood drove the gauge off GREEN (AMBER/RED)" \
  bash -c "[ '$FLOOD_OVERALL' = 'AMBER' ] || [ '$FLOOD_OVERALL' = 'RED' ]"
am_assert "the footprint ranked the offender #1"          test "$RANK1" -eq 1
am_assert "the footprint flagged it near-limit"           test "$NEARLIMIT" -eq 1
am_assert "the observed rate is OVER the declared band"   test "${RATE:-0}" -gt 50

am_stop_load
am_say "(flood stopped; nothing cut — that's scenario 04's job)"
echo
am_say "Next: bin/access-mgmt 04-revoke-the-spammer"
am_summary
