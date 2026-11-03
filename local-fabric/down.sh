#!/usr/bin/env bash
# down.sh — tear the local demo fabric down and wipe its disposable state.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DC="docker compose"; docker compose version >/dev/null 2>&1 || DC="docker-compose"
( cd "$HERE" && $DC down -v 2>/dev/null ) || true
rm -rf "$HERE/.state" "$HERE/zenoh" "$HERE/profiles"
echo "==> local fabric down; throwaway certs + state wiped."
