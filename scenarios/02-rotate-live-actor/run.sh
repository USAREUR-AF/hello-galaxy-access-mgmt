#!/usr/bin/env bash
# Scenario 02 — Rotate a live actor in place.
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib/access-mgmt.sh"
am_parse_env "$@"; set -- "${AM_ARGS[@]}"

am_banner "Rotate a live actor — fresh leaf, same identity, zero downtime" \
          "weather-vane keeps publishing across a credential rotation."

am_preflight || exit 1

if ! am_is_local; then
  am_step "On a live fabric: the production rotate command"
  am_say "To rotate a real actor's credential in place, an operator runs:"
  printf '      %sgoat admin rotate <anchor|alias>%s\n' "$C_BOLD" "$C_RESET"
  am_say "It mints a fresh leaf for the same slot anchor and prints a one-time bundle"
  am_say "URL; the anchor / alias / write namespace / ACL are all unchanged."
  am_honest "the full publish → rotate → still-publishing arc runs in --env local"
  am_honest "(it needs to swap the cert + observe). Re-run with: --env local"
  exit 0
fi

WEATHER="$(am_anchor weather-vane)"
CERT="$AM_FAB/zenoh/tls/$WEATHER-cert.pem"
fpr() { openssl x509 -in "$CERT" -noout -fingerprint -sha256 2>/dev/null | sed 's/.*=//'; }
cfg_hash() { shasum -a 256 "$AM_FAB/.state/router.json5" | awk '{print $1}'; }

am_step "1 — weather-vane is alive and publishing on its slot"
am_note "slot anchor: $WEATHER"
if am_observe_publish weather-vane "$WEATHER/sensor/temp" "pre-rotate-$$"; then
  am_ok "publishing — observer saw it land (pre-rotation)"; PRE_OK=1
else
  am_fail "weather-vane is not publishing"; PRE_OK=0
fi
OLD_FPR="$(fpr)"; OLD_CFG="$(cfg_hash)"
am_note "leaf fingerprint (old): ${OLD_FPR:0:23}…"
am_note "router config hash:     ${OLD_CFG:0:16}…"

am_step "2 — Rotate the credential IN PLACE"
am_cmd "goat admin rotate weather-vane   (here: local-fabric/rotate.sh)"
bash "$AM_FAB/rotate.sh" weather-vane | sed 's/^/    /'

NEW_FPR="$(fpr)"; NEW_CFG="$(cfg_hash)"
am_note "leaf fingerprint (new): ${NEW_FPR:0:23}…"
am_note "router config hash:     ${NEW_CFG:0:16}…"

am_step "3 — weather-vane keeps publishing — on the NEW leaf, same slot"
if am_observe_publish weather-vane "$WEATHER/sensor/temp" "post-rotate-$$"; then
  am_ok "still publishing — observer saw it land (post-rotation)"; POST_OK=1
else
  am_fail "weather-vane stopped publishing after rotation"; POST_OK=0
fi

am_step "Verify the rotation was safe + dynamic"
am_assert "actor was publishing before rotation"            test "$PRE_OK"  -eq 1
am_assert "actor still publishing after rotation"           test "$POST_OK" -eq 1
am_assert "the leaf certificate genuinely changed"          test "$OLD_FPR" != "$NEW_FPR"
am_assert "the slot anchor did NOT move (same identity)"    bash -c "openssl x509 -in '$CERT' -noout -subject | grep -q 'CN *= *$WEATHER'"
am_assert "the router ACL was untouched (config unchanged)" test "$OLD_CFG" = "$NEW_CFG"

am_honest "the old leaf is not cryptographically revoked (no CRL/OCSP by design);"
am_honest "for compromise, compose rotation with the mesh-first cut in scenario 04."

echo
am_say "Next: bin/access-mgmt 03-detect-the-spammer"
am_summary
