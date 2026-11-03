# shellcheck shell=bash
# lib-fabric.sh — the single source of truth for the local demo fabric's
# PRE-CUT UUID SLOT POOL and the router ACL rendered from it.
#
# This file is the whole point of the repo made concrete. The goat fabric runs a
# brokerless Zenoh router whose access-control list is STATIC — it cannot be
# hot-edited per tenant while the router serves traffic. So how do we
# rotate and revoke identities *dynamically*? We don't make the ACL dynamic — we
# PRE-CUT a pool of identity slots into it up front:
#
#   * Each slot is a fixed 32-hex UUID "anchor".
#   * For each slot, a write grant `<anchor>/**` (+ `volatile/<anchor>/**`) is
#     baked into the static ACL, keyed on the cert COMMON NAME == that anchor.
#   * The grant follows the SLOT, never a particular leaf certificate.
#
# That one decision is what makes both lifecycle operations cheap and dynamic:
#
#   ROTATE  = mint a fresh leaf for the SAME anchor and swap it on the peer.
#             The ACL keys on the anchor, which did not move, so NOTHING in the
#             router changes — no re-render, no reload. The credential refreshes
#             while the identity (the slot) persists.
#
#   REVOKE  = mesh-first cut (delete the peer — the authoritative, instant half)
#             plus reclaiming the slot: remove that anchor's subject+policy from
#             the ACL and reload. The slot returns to the pool, ready to re-issue.
#
# Reads stay permissive in every mode (the fabric is a write-integrity layer;
# read secrecy is enforced elsewhere). Only write grants move.

FAB_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAB_STATE="$FAB_HERE/.state"
FAB_TLS="$FAB_HERE/zenoh/tls"
FAB_PROF="$FAB_HERE/profiles"
FAB_ROSTER="$FAB_HERE/roster/slot-pool.tsv"

# fab_mint_leaf <cn>  — mint a fresh leaf cert for <cn>, signed by the demo CA,
# into $FAB_TLS/<cn>-{cert,key}.pem. A fresh RSA key + fresh serial every call,
# so re-minting the SAME cn (a ROTATION) yields a genuinely different leaf that
# still presents the same identity (CN). The CA must already exist.
fab_mint_leaf() {
  local cn="$1" san="DNS:$1"
  openssl genrsa -out "$FAB_TLS/$cn-key.pem" 2048 >/dev/null 2>&1
  openssl req -new -key "$FAB_TLS/$cn-key.pem" -subj "/O=hello-galaxy-access-mgmt/CN=$cn" \
    -out "$FAB_TLS/$cn.csr" >/dev/null 2>&1
  openssl x509 -req -in "$FAB_TLS/$cn.csr" -CA "$FAB_TLS/ca-root-cert.pem" -CAkey "$FAB_TLS/ca-key.pem" \
    -CAcreateserial -days 30 -sha256 \
    -extfile <(printf 'subjectAltName=%s\nextendedKeyUsage=serverAuth,clientAuth\n' "$san") \
    -out "$FAB_TLS/$cn-cert.pem" >/dev/null 2>&1
  rm -f "$FAB_TLS/$cn.csr"
}

# fab_make_profile <persona-dir> <cert-cn>  — assemble a goat profile dir that
# dials the local router with the given leaf. Re-runnable; used at first mint
# and on every rotation (which just drops a fresh cert/key into the same dir).
fab_make_profile() {
  local who="$1" cn="$2" dir="$FAB_PROF/$1/contexts/local"
  mkdir -p "$dir"
  cp "$FAB_TLS/$cn-cert.pem" "$dir/mtls.cert.pem"
  cp "$FAB_TLS/$cn-key.pem"  "$dir/mtls.key.pem"
  cp "$FAB_TLS/ca-root-cert.pem" "$dir/ca-roots.pem"
  printf 'current_context = "local"\n' > "$FAB_PROF/$who/config.toml"
  cat > "$dir/profile.toml" <<EOF
# hello-galaxy-access-mgmt local fabric — $who
portal_endpoint = "https://portal.local.invalid"
router_endpoint = "tls/127.0.0.1:7447"
device_id = "$who"
EOF
  : > "$dir/portal.token"
}

# pad8 <8-hex-prefix> -> a full 32-hex anchor (prefix + trailing zeros).
# Keeps the anchors readable in narration while staying valid slot ids.
pad8() { printf '%-32s' "$1" | tr ' ' '0'; }

# --- the pre-cut slot pool --------------------------------------------------
# Four slots are pre-cut into the ACL. Three are ALLOCATED to demo actors; one
# is FREE — already authorised, just waiting for a peer to be handed its cert
# (that is what "pre-cut" means: the authorisation decision is provisioned
# before anyone shows up). Edit nothing here without re-running gen-certs.sh.
FAB_ANCHOR_WEATHER="$(pad8 a11ce551)"   # weather-vane — the LIVE actor we ROTATE
FAB_ANCHOR_STEADY="$(pad8 5addecaf)"    # steady-eddie — a well-behaved control producer
FAB_ANCHOR_LOUD="$(pad8 f100ded0)"      # loud-mouth   — the SPAMMER we DETECT + REVOKE
FAB_ANCHOR_FREE="$(pad8 face5107)"      # (unallocated) — a free slot held open in the pool

# alias -> anchor, for narration + the `roster` view. Kept in lockstep with the
# certs minted by gen-certs.sh and the ACL rendered below.
fab_pool() {
  printf '%s\t%s\t%s\n' weather-vane "$FAB_ANCHOR_WEATHER" "ALLOCATED — live actor (rotated)"
  printf '%s\t%s\t%s\n' steady-eddie "$FAB_ANCHOR_STEADY"  "ALLOCATED — control producer"
  printf '%s\t%s\t%s\n' loud-mouth   "$FAB_ANCHOR_LOUD"    "ALLOCATED — spammer (revoked)"
  printf '%s\t%s\t%s\n' '(free)'     "$FAB_ANCHOR_FREE"     "FREE — pre-cut, awaiting a holder"
}

# render_router_config <mode>   mode = full | revoke
#   Emits a zenohd config.json5 to stdout. In `full` mode every allocated slot
#   (and the free slot) carries its baked-in write grant. In `revoke` mode the
#   loud-mouth slot's grant is removed — the Zenoh-layer half of a production
#   mesh-first revocation (de-authorise the cert / reclaim the slot). Rotation
#   never calls this: a rotated leaf keeps the same anchor, so the config below
#   is byte-for-byte identical before and after a rotation.
render_router_config() {
  local mode="${1:-full}"

  # The loud-mouth slot — present in `full`, reclaimed (omitted) in `revoke`.
  local loud_subject="" loud_rule="" loud_policy=""
  if [ "$mode" = "full" ]; then
    loud_subject="      { id: \"s-loud\", cert_common_names: [\"$FAB_ANCHOR_LOUD\"] },"
    loud_rule="      { id: \"w-loud\", messages: [\"put\",\"delete\"], flows: [\"ingress\"], permission: \"allow\",
        key_exprs: [\"$FAB_ANCHOR_LOUD/**\", \"volatile/$FAB_ANCHOR_LOUD/**\"] },"
    loud_policy="      { rules: [\"w-loud\"], subjects: [\"s-loud\"] },"
  fi

  cat <<EOF
// hello-galaxy-access-mgmt local fabric — zenohd router config ($mode).
// Generated by local-fabric/lib-fabric.sh from the PRE-CUT SLOT POOL.
// mTLS-gated, default-deny ACL. Reads permissive; writes scoped per slot anchor.
//
// Every "w-<slot>" rule below is a PRE-CUT write grant keyed on a cert CN that
// equals the slot's 32-hex anchor. A leaf cert authorises a write iff its CN
// matches a granted slot — so a rotated leaf (same CN) is admitted with zero
// config change, and a reclaimed slot (rule removed) denies every leaf at once.
{
  mode: "router",
  listen: { endpoints: ["tls/0.0.0.0:7447"] },
  transport: {
    link: {
      tls: {
        listen_certificate: "/etc/zenoh/tls/router-cert.pem",
        listen_private_key:  "/etc/zenoh/tls/router-key.pem",
        root_ca_certificate: "/etc/zenoh/tls/ca-root-cert.pem",
        enable_mtls: true,
        verify_name_on_connect: false,
      },
    },
  },
  access_control: {
    enabled: true,
    default_permission: "deny",
    rules: [
      // Any mTLS peer may subscribe/query and RECEIVE samples on any key
      // (permissive reads — the fabric enforces write integrity, not read secrecy).
      { id: "sub-any", messages: ["declare_subscriber","query","reply"], flows: ["ingress","egress"],
        permission: "allow", key_exprs: ["**"] },
      { id: "recv-any", messages: ["put","delete"], flows: ["egress"],
        permission: "allow", key_exprs: ["**"] },

      // The fabric-health meter writes the health weather + per-producer footprints.
      { id: "w-meter", messages: ["put","delete"], flows: ["ingress"], permission: "allow",
        key_exprs: ["ops/fabric/**"] },
      // The operator publishes on its own control namespace.
      { id: "w-operator", messages: ["put","delete"], flows: ["ingress"], permission: "allow",
        key_exprs: ["ops/access/**"] },

      // ---- PRE-CUT SLOT POOL: one write grant per slot anchor ----
      { id: "w-weather", messages: ["put","delete"], flows: ["ingress"], permission: "allow",
        key_exprs: ["$FAB_ANCHOR_WEATHER/**", "volatile/$FAB_ANCHOR_WEATHER/**"] },
      { id: "w-steady", messages: ["put","delete"], flows: ["ingress"], permission: "allow",
        key_exprs: ["$FAB_ANCHOR_STEADY/**", "volatile/$FAB_ANCHOR_STEADY/**"] },
$loud_rule
      { id: "w-free", messages: ["put","delete"], flows: ["ingress"], permission: "allow",
        key_exprs: ["$FAB_ANCHOR_FREE/**", "volatile/$FAB_ANCHOR_FREE/**"] },
    ],
    subjects: [
      { id: "any-mtls", link_protocols: ["tls"] },
      { id: "s-meter", cert_common_names: ["fabric-health-trial-peer"] },
      { id: "s-operator", cert_common_names: ["operator"] },
      // ---- a subject per slot anchor (the CN the leaf must present) ----
      { id: "s-weather", cert_common_names: ["$FAB_ANCHOR_WEATHER"] },
      { id: "s-steady",  cert_common_names: ["$FAB_ANCHOR_STEADY"] },
$loud_subject
      { id: "s-free",    cert_common_names: ["$FAB_ANCHOR_FREE"] },
    ],
    policies: [
      { rules: ["sub-any","recv-any"], subjects: ["any-mtls"] },
      { rules: ["w-meter"], subjects: ["s-meter"] },
      { rules: ["w-operator"], subjects: ["s-operator"] },
      { rules: ["w-weather"], subjects: ["s-weather"] },
      { rules: ["w-steady"], subjects: ["s-steady"] },
$loud_policy
      { rules: ["w-free"], subjects: ["s-free"] },
    ],
  },
}
EOF
}
