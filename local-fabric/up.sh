#!/usr/bin/env bash
# up.sh — bring up the self-contained local demo fabric.
#   - mints the throwaway CA + a leaf per allocated slot + persona profiles
#   - renders the router ACL from the pre-cut slot pool (full — all granted)
#   - starts the real zenohd + the real goat-fabric-health meter (demo-scaled)
#   - waits until the meter is publishing health
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib-fabric.sh"
cd "$HERE"

command -v docker  >/dev/null || { echo "need docker"  >&2; exit 1; }
command -v openssl >/dev/null || { echo "need openssl" >&2; exit 1; }
command -v goat    >/dev/null || { echo "need goat on PATH (build it from https://github.com/usareur-af/goatcore)" >&2; exit 1; }
DC="docker compose"; docker compose version >/dev/null 2>&1 || DC="docker-compose"

echo "==> minting throwaway CA + slot leaves + persona profiles"
bash "$HERE/gen-certs.sh"

echo "==> rendering router config from the pre-cut slot pool (full — all slots granted)"
mkdir -p "$FAB_STATE"
render_router_config full > "$FAB_STATE/router.json5"

echo "==> pulling images + starting the fabric"
$DC pull -q 2>/dev/null || true
$DC up -d

echo -n "==> waiting for the meter to publish health "
ok=0
for _ in $(seq 1 24); do
  if goat --profile-dir "$HERE/profiles/operator" health 2>/dev/null | grep -q "FABRIC:"; then ok=1; break; fi
  echo -n "."; sleep 2
done
echo
if [ "$ok" -eq 1 ]; then
  echo "==> fabric is UP. The gauge:"
  goat --profile-dir "$HERE/profiles/operator" health 2>/dev/null | sed 's/^/    /'
  echo
  echo "    The slot pool:"
  fab_pool | awk -F'\t' '{printf "      %-13s %s  %s\n",$1,$2,$3}'
  echo
  echo "    Run a scenario, e.g.:"
  echo "      bin/access-mgmt 02-rotate-live-actor --env local"
  echo "      bin/access-mgmt 04-revoke-the-spammer --env local"
  echo "    Tear down with: local-fabric/down.sh"
else
  echo "!! meter did not start publishing in time. Inspect with:"
  echo "     $DC -f $HERE/docker-compose.yml logs"
  exit 1
fi
