#!/usr/bin/env bash
# gen-certs.sh — mint a throwaway CA + one leaf per pre-cut slot (and the
# operator + meter). Everything here is DISPOSABLE and never leaves your
# machine; it exists only so the local zenohd can enforce a real, identity-bound
# ACL of the same shape as a production fabric — the ACL we then rotate a leaf
# within and revoke a slot out of.
#
# Each SLOT persona's cert CN == its 32-hex anchor, so the router's pre-cut
# write grant (keyed on CN) admits it. The operator + meter carry plain CNs.
#
# Re-runnable: regenerates cleanly each time.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib-fabric.sh"

rm -rf "$FAB_TLS" "$FAB_PROF"
mkdir -p "$FAB_TLS" "$FAB_HERE/roster"

echo "==> throwaway CA"
openssl genrsa -out "$FAB_TLS/ca-key.pem" 2048 >/dev/null 2>&1
openssl req -x509 -new -nodes -key "$FAB_TLS/ca-key.pem" -sha256 -days 30 \
  -subj "/O=hello-galaxy-access-mgmt/CN=access-mgmt-local-CA" \
  -out "$FAB_TLS/ca-root-cert.pem" >/dev/null 2>&1

echo "==> router server cert"
# Router leaf needs the dial names/IP as SANs (clients verify the chain; the
# router does not verify client names — verify_name_on_connect:false).
openssl genrsa -out "$FAB_TLS/router-key.pem" 2048 >/dev/null 2>&1
openssl req -new -key "$FAB_TLS/router-key.pem" -subj "/O=hello-galaxy-access-mgmt/CN=access-mgmt-router" \
  -out "$FAB_TLS/router.csr" >/dev/null 2>&1
openssl x509 -req -in "$FAB_TLS/router.csr" -CA "$FAB_TLS/ca-root-cert.pem" -CAkey "$FAB_TLS/ca-key.pem" \
  -CAcreateserial -days 30 -sha256 \
  -extfile <(printf 'subjectAltName=DNS:localhost,DNS:access-mgmt-router,IP:127.0.0.1\nextendedKeyUsage=serverAuth,clientAuth\n') \
  -out "$FAB_TLS/router-cert.pem" >/dev/null 2>&1
rm -f "$FAB_TLS/router.csr"

echo "==> infra leaves (operator, meter)"
fab_mint_leaf operator
fab_mint_leaf fabric-health-trial-peer
# The meter image runs as a non-root user (65532) and reads this throwaway key
# through a bind mount; openssl writes keys 0600, so open it for reading.
chmod 0644 "$FAB_TLS/fabric-health-trial-peer-key.pem"

echo "==> slot leaves (CN == anchor) for the allocated slots"
fab_mint_leaf "$FAB_ANCHOR_WEATHER"
fab_mint_leaf "$FAB_ANCHOR_STEADY"
fab_mint_leaf "$FAB_ANCHOR_LOUD"
# NOTE: the free slot is deliberately NOT minted — it is authorised in the ACL
# but no leaf exists yet. Onboarding a new actor = minting a leaf for it.

echo "==> goat profiles"
fab_make_profile operator     operator
fab_make_profile weather-vane "$FAB_ANCHOR_WEATHER"
fab_make_profile steady-eddie "$FAB_ANCHOR_STEADY"
fab_make_profile loud-mouth   "$FAB_ANCHOR_LOUD"

echo "==> writing roster view"
fab_pool > "$FAB_ROSTER"

echo "==> done."
echo "    Slot pool:"
fab_pool | awk -F'\t' '{printf "      %-13s %s  %s\n",$1,$2,$3}'
