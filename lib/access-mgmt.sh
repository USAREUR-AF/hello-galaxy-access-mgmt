# shellcheck shell=bash
# access-mgmt.sh — shared library for the hello-galaxy-access-mgmt scenarios.
#
# Sourced by every scenario driver. Provides environment resolution, the `goat`
# invocation wrapper, slot-pool helpers, pretty narration, and lightweight
# assertions.
#
# Two execution modes, selected by AM_ENV (or `--env`):
#   - local (DEFAULT) — the self-contained docker-compose fabric (real zenohd +
#     the real goat-fabric-health meter) under local-fabric/. The rotate/revoke
#     arcs need control of the router, so this is the default.
#   - <context>       — a live goat context (any goatnet you have access to). Read-only here: it shows
#     the production command + proves the standing ACL floor is live, and is
#     honest that the full lifecycle arc runs in --env local.

set -o pipefail

AM_LIB="${BASH_SOURCE[0]}"
AM_ROOT="$(cd "$(dirname "$AM_LIB")/.." && pwd)"
export AM_ROOT
AM_FAB="$AM_ROOT/local-fabric"
# shellcheck source=/dev/null
source "$AM_FAB/lib-fabric.sh"

AM_ENV="${AM_ENV:-local}"

# am_parse_env "$@"; set -- "${AM_ARGS[@]}"
am_parse_env() {
  AM_ARGS=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --env) AM_ENV="$2"; shift 2 ;;
      --env=*) AM_ENV="${1#--env=}"; shift ;;
      *) AM_ARGS+=("$1"); shift ;;
    esac
  done
  export AM_ENV
}
am_is_local() { [ "$AM_ENV" = "local" ]; }

# --- goat invocation --------------------------------------------------------
# am_goat            -> the operator identity (observe / health / cut)
# am_goat_as <who>   -> a named slot persona (local mode); live maps to context
am_goat() {
  if am_is_local; then goat --profile-dir "$AM_FAB/profiles/operator" "$@"
  else goat --context "$AM_ENV" "$@"; fi
}
am_goat_as() {
  local who="$1"; shift
  if am_is_local; then goat --profile-dir "$AM_FAB/profiles/$who" "$@"
  else goat --context "$AM_ENV" "$@"; fi
}

# --- slot pool helpers ------------------------------------------------------
# am_anchor <alias>  -> the 32-hex slot anchor for a persona alias.
am_anchor() { fab_pool | awk -F'\t' -v a="$1" '$1==a {print $2}'; }
# am_pool            -> the roster table (alias / anchor / state).
am_pool() { fab_pool; }

# --- presentation -----------------------------------------------------------
if [ -t 1 ] && [ "${NO_COLOR:-}" = "" ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_CYAN=$'\033[36m'; C_BLUE=$'\033[34m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_CYAN=""; C_BLUE=""
fi

AM_STEP=0
am_step() { AM_STEP=$((AM_STEP+1)); printf '\n%s%s── Step %d ─ %s%s\n' "$C_BOLD" "$C_CYAN" "$AM_STEP" "$1" "$C_RESET"; }
am_say()   { printf '%s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }
am_note()  { printf '%s  • %s%s\n' "$C_BLUE" "$*" "$C_RESET"; }
am_cmd()   { printf '%s$ %s%s\n' "$C_BOLD" "$*" "$C_RESET"; }
am_ok()    { printf '%s  ✓ %s%s\n' "$C_GREEN" "$*" "$C_RESET"; }
am_warn()  { printf '%s  ! %s%s\n' "$C_YELLOW" "$*" "$C_RESET"; }
am_fail()  { printf '%s  ✗ %s%s\n' "$C_RED" "$*" "$C_RESET"; }
am_honest(){ printf '%s  ⓘ honesty: %s%s\n' "$C_YELLOW" "$*" "$C_RESET"; }
am_banner() {
  printf '\n%s%s════════════════════════════════════════════════════════════%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
  printf '%s%s  %s%s\n' "$C_BOLD" "$C_CYAN" "$1" "$C_RESET"
  printf '%s%s════════════════════════════════════════════════════════════%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
  [ -n "${2:-}" ] && printf '%s  %s%s\n' "$C_DIM" "$2" "$C_RESET"
  printf '%s  env: %s%s\n' "$C_DIM" "$AM_ENV" "$C_RESET"
}

# --- assertions -------------------------------------------------------------
AM_PASS=0; AM_FAIL=0
am_assert() { local d="$1"; shift; if "$@"; then AM_PASS=$((AM_PASS+1)); am_ok "$d"; return 0; else AM_FAIL=$((AM_FAIL+1)); am_fail "$d"; return 1; fi; }
am_summary() {
  printf '\n%s%s── result ─ %d passed, %d failed%s\n' \
    "$C_BOLD" "$( [ "$AM_FAIL" -eq 0 ] && echo "$C_GREEN" || echo "$C_RED")" \
    "$AM_PASS" "$AM_FAIL" "$C_RESET"
  [ "$AM_FAIL" -eq 0 ]
}

# --- ground-truth publish/observe helpers -----------------------------------
# am_observe_publish <pub-persona> <key> <payload>  -> 0 iff a real subscriber
#   saw the payload land. The authoritative "it was admitted + routed" signal.
am_observe_publish() {
  local who="$1" key="$2" payload="$3" prefix="${2%/*}/**"
  local log; log="$(mktemp -t am-obs.XXXXXX)"
  am_goat sub "$prefix" >"$log" 2>/dev/null & local sp=$!
  sleep 2
  am_goat_as "$who" pub "$key" --payload "$payload" >/dev/null 2>&1
  sleep 3; kill "$sp" 2>/dev/null
  AM_OBS_SEEN="$(grep -c . "$log" 2>/dev/null)"; AM_OBS_SEEN="${AM_OBS_SEEN//[^0-9]/}"; AM_OBS_SEEN="${AM_OBS_SEEN:-0}"
  grep -qF -- "$payload" "$log"
}

# am_count_after_cut <pub-persona> <anchor> -> samples a denied writer lands (0).
am_count_after_cut() {
  local who="$1" anchor="$2"
  local log; log="$(mktemp -t am-cut.XXXXXX)"
  am_goat sub "$anchor/sensor/**" >"$log" 2>/dev/null & local sp=$!
  sleep 2
  am_goat_as "$who" mock "$anchor/sensor/postcut" --rate 200 --count 800 >/dev/null 2>&1 &
  sleep 8; kill "$sp" 2>/dev/null; pkill -f "goat.*mock" 2>/dev/null
  local n; n="$(grep -c . "$log" 2>/dev/null)"; echo "${n//[^0-9]/}"
}

# --- load generation --------------------------------------------------------
AM_LOAD_PIDS=()
am_start_load() {
  local who="$1" key="$2" rate="$3" count="${4:-100000}"
  am_goat_as "$who" mock "$key" --rate "$rate" --count "$count" >/dev/null 2>&1 &
  AM_LOAD_PIDS+=($!); echo "${AM_LOAD_PIDS[-1]}"
}
am_stop_load() { local p; for p in "${AM_LOAD_PIDS[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done; pkill -f "goat.*mock" 2>/dev/null; AM_LOAD_PIDS=(); }
trap 'am_stop_load' EXIT INT TERM

# Extract the overall FABRIC state word + a class's msgs/s from a health capture.
am_overall() { printf '%s\n' "$1" | sed -n 's/^FABRIC: *\([A-Z]*\).*/\1/p' | head -1; }
am_class_rate() { printf '%s\n' "$1" | awk -v c="$2" '$1==c {print $2; exit}'; }

# --- preflight --------------------------------------------------------------
am_preflight() {
  command -v goat >/dev/null 2>&1 || { am_fail "goat CLI not on PATH — see README prerequisites"; return 1; }
  if am_is_local && ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^access-mgmt-router$'; then
    am_fail "local fabric not running — start it with:  local-fabric/up.sh"; return 1
  fi
  return 0
}
