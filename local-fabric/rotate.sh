#!/usr/bin/env bash
# rotate.sh — rotate a live actor's credential IN PLACE.
#
# This is the local-fabric realisation of `goat admin rotate <anchor|alias>`
# (ADR 1044). It mints a FRESH leaf cert for the SAME slot anchor and swaps it
# into the actor's profile. Because the router's write grant keys on the anchor
# (the cert CN) — which does not move — the ACL is NOT re-rendered and the router
# is NOT reloaded. The credential refreshes; the identity (the slot) persists.
#
# The old leaf is not cryptographically invalidated (goat ships no CRL/OCSP by
# design, ADR 0407); in production the mesh-first cut (delete the peer) is what
# kills the old key before its short lifetime expires. Here we only swap.
#
# usage:  rotate.sh <alias>     # default: weather-vane
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib-fabric.sh"

alias_in="${1:-weather-vane}"
anchor="$(fab_pool | awk -F'\t' -v a="$alias_in" '$1==a {print $2}')"
[ -n "$anchor" ] || { echo "unknown slot alias: $alias_in" >&2; exit 2; }

leaf_fpr() { openssl x509 -in "$FAB_TLS/$anchor-cert.pem" -noout -fingerprint -sha256 2>/dev/null | sed 's/.*=//'; }
leaf_serial() { openssl x509 -in "$FAB_TLS/$anchor-cert.pem" -noout -serial 2>/dev/null | sed 's/.*=//'; }

OLD_FPR="$(leaf_fpr)"; OLD_SERIAL="$(leaf_serial)"
echo "==> rotating slot $alias_in ($anchor)"
echo "    old leaf  serial=$OLD_SERIAL"
echo "    old leaf  sha256=$OLD_FPR"

# Mint a fresh leaf for the SAME CN/anchor, and refresh the profile in place.
fab_mint_leaf "$anchor"
fab_make_profile "$alias_in" "$anchor"

NEW_FPR="$(leaf_fpr)"; NEW_SERIAL="$(leaf_serial)"
echo "    new leaf  serial=$NEW_SERIAL"
echo "    new leaf  sha256=$NEW_FPR"
echo
if [ "$OLD_FPR" != "$NEW_FPR" ]; then
  echo "    ✓ leaf changed (fresh key + serial)"
else
  echo "    ✗ leaf did NOT change — rotation failed" >&2; exit 1
fi
echo "    ✓ anchor unchanged: $anchor  (same write namespace, same ACL grant)"
echo "    ✓ router config NOT re-rendered, router NOT reloaded"
