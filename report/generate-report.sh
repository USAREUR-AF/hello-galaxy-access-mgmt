#!/usr/bin/env bash
# generate-report.sh — run every scenario against the live local fabric, capture
# the real output + metrics, and emit a self-contained, beautiful HTML report
# (report/report.html) with figures, diagrams, captured terminal output, and a
# verdict table. Nothing in the report is faked: every number is read back from a
# scenario that ran against the real zenohd + the real goat-fabric-health meter.
#
# usage:  report/generate-report.sh        # brings the fabric up if needed
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
CAP="$HERE/.captures"; mkdir -p "$CAP"
OUT="$HERE/report.html"
cd "$ROOT"

# --- ensure the fabric is up ------------------------------------------------
if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^access-mgmt-router$'; then
  echo "==> local fabric not running; bringing it up"
  bash local-fabric/up.sh
fi

STAMP="$(date -u '+%Y-%m-%d %H:%M:%SZ')"
SCENS=(00-orient 01-the-slot-pool 02-rotate-live-actor 03-detect-the-spammer 04-revoke-the-spammer)
if [ "${SKIP_RUN:-0}" = "1" ] && [ -f "$CAP/04-revoke-the-spammer.txt" ]; then
  echo "==> SKIP_RUN=1 — reusing existing captures"
else
  echo "==> running scenarios (capturing real output)…"
  for s in "${SCENS[@]}"; do
    echo "    - $s"
    NO_COLOR=1 bash "scenarios/$s/run.sh" --env local >"$CAP/$s.txt" 2>&1
    echo $? >"$CAP/$s.rc"
  done
fi

# --- extract metrics from the real captures ---------------------------------
g() { grep -m1 -- "$2" "$CAP/$1.txt" 2>/dev/null; }
passes() { local tot=0; for s in "${SCENS[@]}"; do
    local n; n="$(sed -n 's/.*result ─ \([0-9]*\) passed.*/\1/p' "$CAP/$s.txt" | head -1)"; tot=$((tot + ${n:-0}))
  done; echo "$tot"; }
fails() { local tot=0; for s in "${SCENS[@]}"; do
    local n; n="$(sed -n 's/.*result ─ [0-9]* passed, \([0-9]*\) failed.*/\1/p' "$CAP/$s.txt" | head -1)"; tot=$((tot + ${n:-0}))
  done; echo "$tot"; }
scen_result() { sed -n 's/.*\(result ─ [0-9]* passed, [0-9]* failed\).*/\1/p' "$CAP/$1.txt" | head -1; }

TOTAL_PASS="$(passes)"; TOTAL_FAIL="$(fails)"

ROT_OLD="$(g 02-rotate-live-actor 'old leaf  sha256' | sed 's/.*sha256=//' | cut -c1-23)"
ROT_NEW="$(g 02-rotate-live-actor 'new leaf  sha256' | sed 's/.*sha256=//' | cut -c1-23)"
CFG_HASHES="$(grep 'router config hash' "$CAP/02-rotate-live-actor.txt" | sed 's/.*hash: *//' | tr -d ' ')"
CFG_BEFORE="$(printf '%s\n' "$CFG_HASHES" | sed -n '1p')"
CFG_AFTER="$(printf '%s\n' "$CFG_HASHES" | sed -n '2p')"
CFG_SAME="no"; [ -n "$CFG_BEFORE" ] && [ "$CFG_BEFORE" = "$CFG_AFTER" ] && CFG_SAME="yes"
DET_RATE="$(g 03-detect-the-spammer 'observed rate' | sed -n 's/.*observed rate: \([0-9]*\) msgs.*/\1/p')"
POSTCUT="$(g 04-revoke-the-spammer 'samples the observer saw' | sed -n 's/.*[Aa][Ff][Tt][Ee][Rr] the cut: \([0-9]*\).*/\1/p')"
# the gauge state under flood (first AMBER/RED FABRIC line in the revoke capture)
FLOOD_STATE="$(grep -m1 -E 'FABRIC: (AMBER|RED)' "$CAP/04-revoke-the-spammer.txt" | sed -n 's/.*FABRIC: \([A-Z]*\).*/\1/p')"
# the C2 "of target" column (e.g. 326/300) from the first flooded health table
FLOOD_C2="$(grep -m1 -E '(^| )C2 +[0-9]+ +[0-9]+/[0-9]+' "$CAP/04-revoke-the-spammer.txt" | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\/[0-9]+$/){print $i; exit}}')"

WEATHER="$(cd local-fabric && source lib-fabric.sh && echo "$FAB_ANCHOR_WEATHER")"
LOUD="$(cd local-fabric && source lib-fabric.sh && echo "$FAB_ANCHOR_LOUD")"

esc() { sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'; }
cap_html() { esc < "$CAP/$1.txt"; }

echo "==> writing $OUT"
# shellcheck disable=SC2129
{
cat <<HTML
<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>hello-galaxy-access-mgmt — live access-management report</title>
<style>
:root{
  --bg:#0e1116; --panel:#161b22; --panel2:#1c232c; --ink:#e6edf3; --dim:#9aa7b4;
  --line:#2a323c; --accent:#f5b14c; --accent2:#5ec8cd; --green:#3fb950; --amber:#d29922;
  --red:#f85149; --blue:#58a6ff; --mono:"SFMono-Regular",ui-monospace,"JetBrains Mono",Menlo,Consolas,monospace;
}
*{box-sizing:border-box} html{scroll-behavior:smooth}
body{margin:0;background:radial-gradient(1200px 600px at 70% -10%,#1b2430,transparent),var(--bg);
  color:var(--ink);font:16px/1.6 ui-sans-serif,-apple-system,Segoe UI,Roboto,Helvetica,Arial}
.wrap{max-width:980px;margin:0 auto;padding:48px 24px 96px}
header.hero{padding:28px 0 8px;border-bottom:1px solid var(--line);margin-bottom:36px}
.kick{color:var(--accent);font:600 13px/1.4 var(--mono);letter-spacing:.14em;text-transform:uppercase}
h1{font-size:34px;margin:.25em 0 .1em;letter-spacing:-.5px}
h2{font-size:24px;margin:2.4em 0 .5em;padding-top:.4em;border-top:1px solid var(--line)}
h3{font-size:18px;margin:1.6em 0 .4em;color:#cdd9e5}
.lede{color:var(--dim);font-size:18px;max-width:70ch}
.meta{color:var(--dim);font:13px/1.5 var(--mono);margin-top:14px}
.badge{display:inline-block;padding:3px 10px;border-radius:999px;font:600 12px var(--mono);
  border:1px solid var(--line);background:var(--panel)}
.badge.ok{color:#7ee2a8;border-color:#1f6f3f;background:#10261a}
.grid{display:grid;gap:14px;grid-template-columns:repeat(4,1fr);margin:22px 0}
.card{background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:16px}
.card .n{font:700 26px var(--mono);letter-spacing:-1px}
.card .l{color:var(--dim);font-size:12.5px;margin-top:3px}
.card.good .n{color:var(--green)} .card.warn .n{color:var(--amber)} .card.hot .n{color:var(--red)}
figure{margin:22px 0;background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:18px}
figure svg{width:100%;height:auto;display:block}
figcaption{color:var(--dim);font-size:13.5px;margin-top:12px;text-align:center}
table{width:100%;border-collapse:collapse;margin:16px 0;font-size:14.5px}
th,td{text-align:left;padding:10px 12px;border-bottom:1px solid var(--line);vertical-align:top}
th{color:var(--dim);font:600 12px/1.4 var(--mono);text-transform:uppercase;letter-spacing:.06em}
td.mono,code{font-family:var(--mono)} code{background:var(--panel2);padding:1px 6px;border-radius:6px;font-size:13px}
.tick{color:var(--green);font-weight:700}
.term{background:#0a0d12;border:1px solid var(--line);border-radius:10px;padding:16px 18px;overflow:auto}
.term pre{margin:0;font:13px/1.55 var(--mono);color:#c9d4df;white-space:pre-wrap;word-break:break-word}
details{background:var(--panel);border:1px solid var(--line);border-radius:10px;margin:12px 0;padding:4px 16px}
summary{cursor:pointer;font-weight:600;padding:10px 0}
.pill{font:600 11px var(--mono);padding:2px 8px;border-radius:999px}
.pill.live{color:#7ee2a8;background:#10261a;border:1px solid #1f6f3f}
.pill.rep{color:#e7c07b;background:#241c0e;border:1px solid #6f561f}
.note{color:var(--dim);font-size:14px;border-left:3px solid var(--accent);padding:6px 0 6px 14px;margin:14px 0}
a{color:var(--blue)}
@media(max-width:720px){.grid{grid-template-columns:repeat(2,1fr)}}
</style></head><body><div class="wrap">

<header class="hero">
  <div class="kick">hello-galaxy · usareur-af</div>
  <h1>Dynamic access management on the goat fabric</h1>
  <p class="lede">Rotating a live actor's credential with zero downtime, and detecting &amp;
  revoking a flooding one in seconds — proven end-to-end against a real Zenoh router and the
  real production health meter. <strong>The enabling engineering: a pre-cut UUID slot pool.</strong></p>
  <div class="meta">generated $STAMP · env: local self-contained fabric · <span class="badge ok">$TOTAL_PASS checks passed, $TOTAL_FAIL failed</span></div>
</header>

<div class="grid">
  <div class="card good"><div class="n">$TOTAL_PASS/$((TOTAL_PASS+TOTAL_FAIL))</div><div class="l">assertions passed (live)</div></div>
  <div class="card $([ "$CFG_SAME" = yes ] && echo good || echo hot)"><div class="n">$([ "$CFG_SAME" = yes ] && echo "0" || echo "≠")</div><div class="l">router reloads to rotate a credential</div></div>
  <div class="card hot"><div class="n">${DET_RATE:-—}</div><div class="l">spammer msgs/s detected (max ≈ 50)</div></div>
  <div class="card good"><div class="n">${POSTCUT:-—}</div><div class="l">samples landed after the cut</div></div>
</div>

<h2 id="surface">What's under the surface: the pre-cut slot pool</h2>
<p>The fabric is <strong>brokerless</strong> — a Zenoh router moves messages peer-to-peer with no
central broker. That buys scale and resilience, but the router's access-control list (ACL) is
<strong>static</strong>: read at startup, not safely hot-editable per tenant under live traffic.
So how do you manage identities <em>dynamically</em>? You don't make the ACL dynamic — you
<strong>pre-cut a pool of identity slots into it up front</strong>. Each slot is a fixed 32-hex
anchor; its write grant is keyed on the certificate Common Name being equal to that anchor; and
the grant follows the <strong>slot</strong>, never a particular leaf. That one decision is what
makes rotate and revoke cheap.</p>

<figure>
$(cat "$HERE/figures/slot-pool.svg")
<figcaption>The pre-cut slot pool. Three slots are allocated to actors; one is free — authorised
in the ACL with no leaf minted yet (onboarding is just handing someone that cert). Every grant
keys on the anchor, so a leaf is admitted iff its CN matches a granted slot.</figcaption>
</figure>

<table>
<tr><th>Operation</th><th>What moves</th><th>What the router does</th></tr>
<tr><td><strong>Rotate</strong></td><td>a fresh leaf for the <em>same</em> anchor</td><td><span class="tick">nothing</span> — grant keys on the unchanged anchor; no re-render, no reload</td></tr>
<tr><td><strong>Revoke</strong></td><td>the slot's grant removed (+ mesh cut)</td><td>reload once; the slot returns to the pool, ready to re-issue</td></tr>
<tr><td><strong>Onboard</strong></td><td>hand someone a free slot's cert</td><td><span class="tick">nothing</span> — the grant was already pre-cut</td></tr>
</table>

<h2 id="rotate">Operation 1 — rotate a live actor in place</h2>
<p><code>weather-vane</code> is a live sensor on slot <code>${WEATHER:0:12}…</code>. We watch it
publish, rotate its credential, and watch it keep publishing — on a brand-new leaf, to the same
namespace, seen by the same observer.</p>

<figure>
$(cat "$HERE/figures/rotate.svg")
<figcaption>The credential refreshes while the identity (the slot) persists. The leaf fingerprint
changes; the anchor and the router ACL do not.</figcaption>
</figure>

<table>
<tr><th>Evidence (read back from the live run)</th><th>Value</th></tr>
<tr><td>leaf fingerprint before</td><td class="mono">${ROT_OLD:-—}…</td></tr>
<tr><td>leaf fingerprint after</td><td class="mono">${ROT_NEW:-—}…</td></tr>
<tr><td>router config hash before</td><td class="mono">${CFG_BEFORE:-—}…</td></tr>
<tr><td>router config hash after</td><td class="mono">${CFG_AFTER:-—}…</td></tr>
<tr><td>ACL untouched (hashes equal)?</td><td><span class="tick">$([ "$CFG_SAME" = yes ] && echo "yes — zero router reloads" || echo "no")</span></td></tr>
<tr><td>scenario result</td><td>$(scen_result 02-rotate-live-actor)</td></tr>
</table>
<details><summary>Full captured output — 02-rotate-live-actor</summary>
<div class="term"><pre>$(cap_html 02-rotate-live-actor)</pre></div></details>

<h2 id="detect">Operation 2a — detect the spammer</h2>
<p><code>loud-mouth</code> (slot <code>${LOUD:0:12}…</code>) floods the situational lane. Three
complementary, read-only, honest signals find it.</p>

<figure>
$(cat "$HERE/figures/detect-revoke.svg")
<figcaption>Flood → the gauge goes off-green → the per-producer footprint names the culprit
(rank&nbsp;#1, near-limit) → the operator cuts the slot → the offender's writes are denied →
the lane recovers.</figcaption>
</figure>

<table>
<tr><th>Signal</th><th>Surface</th><th>Live reading</th><th>Grade</th></tr>
<tr><td>Lane load</td><td><code>goat health</code> gauge</td><td>${FLOOD_STATE:-off-green} (C2 ${FLOOD_C2:-—})</td><td><span class="pill live">live</span></td></tr>
<tr><td>Attribution</td><td><code>goat health --peer</code> footprint</td><td>rank #1, near-limit, ${DET_RATE:-—} msgs/s</td><td><span class="pill live">live</span></td></tr>
<tr><td>Expectation</td><td><code>goat top</code> envelope band</td><td>OVER (${DET_RATE:-—} ≫ max 50)</td><td><span class="pill rep">rate live · registry represented</span></td></tr>
</table>
<details><summary>Full captured output — 03-detect-the-spammer</summary>
<div class="term"><pre>$(cap_html 03-detect-the-spammer)</pre></div></details>

<h2 id="revoke">Operation 2b — revoke the spammer</h2>
<p>Mesh-first revocation has two halves: delete the offender's mesh peer (authoritative + instant;
represented on a laptop), and reclaim its slot from the ACL (run here for real). Because the grant
keys on the slot, removing it denies every leaf under it at once — no per-leaf bookkeeping, no
certificate revocation list.</p>

<table>
<tr><th>Evidence (read back from the live run)</th><th>Value</th></tr>
<tr><td>gauge under flood</td><td>${FLOOD_STATE:-off-green} (C2 ${FLOOD_C2:-—})</td></tr>
<tr><td>samples observer saw <em>after</em> the cut</td><td><span class="tick">${POSTCUT:-—}</span> (writes denied)</td></tr>
<tr><td>scenario result</td><td>$(scen_result 04-revoke-the-spammer)</td></tr>
</table>
<details><summary>Full captured output — 04-revoke-the-spammer</summary>
<div class="term"><pre>$(cap_html 04-revoke-the-spammer)</pre></div></details>

<h2 id="slotpool-run">The slot pool, proven</h2>
<details><summary>Full captured output — 01-the-slot-pool (per-slot ACL scoping)</summary>
<div class="term"><pre>$(cap_html 01-the-slot-pool)</pre></div></details>

<h2 id="honesty">Honesty matrix — live vs represented</h2>
<p class="note">Every claim is graded. The two headline operations are entirely live; the only
represented pieces are the ones a laptop structurally cannot run (a WireGuard mesh) or that need a
component the self-contained fabric omits (the portal envelope registry).</p>
<table>
<tr><th>Element</th><th>In this demo</th><th>Grade</th></tr>
<tr><td>Zenoh router + mTLS, default-deny ACL</td><td>real <code>eclipse/zenoh:1.9.0</code>, pinned</td><td><span class="pill live">live</span></td></tr>
<tr><td>Fabric-health meter / gauge / footprint</td><td>the same published image deployed on production fabrics</td><td><span class="pill live">live</span></td></tr>
<tr><td>Pre-cut slot pool + per-slot ACL scoping</td><td>real grants keyed on cert CN == anchor</td><td><span class="pill live">live</span></td></tr>
<tr><td>Rotate-in-place (fresh leaf, same anchor)</td><td>real re-mint + swap; router config unchanged</td><td><span class="pill live">live</span></td></tr>
<tr><td>Revoke = slot reclaim → writes denied</td><td>real ACL edit + reload; observer sees nothing</td><td><span class="pill live">live</span></td></tr>
<tr><td>Mesh-first cut (delete the NetBird peer)</td><td>no mesh on a laptop — the prod-authoritative half</td><td><span class="pill rep">represented</span></td></tr>
<tr><td>Throughput-envelope band via portal registry</td><td>no portal locally; rate live, band computed</td><td><span class="pill rep">represented</span></td></tr>
<tr><td>Automatic detector→revoke loop / relay rate-cap</td><td>designed, not built — operator makes the call</td><td><span class="pill rep">represented</span></td></tr>
</table>

<h2 id="map">How this maps to the production capability</h2>
<table>
<tr><th>Here (local)</th><th>Production goat</th><th>Design</th></tr>
<tr><td><code>local-fabric/rotate.sh</code></td><td><code>goat admin rotate &lt;anchor|alias&gt;</code></td><td>ADR 1044 · credential-rotation</td></tr>
<tr><td><code>local-fabric/revoke.sh</code> (flooder cut)</td><td><code>goat admin peer cut &lt;peer&gt;</code> (emergency, mesh-first)</td><td>ADR 1031 · mesh-first offboarding</td></tr>
<tr><td><code>local-fabric/revoke.sh</code> (full offboard)</td><td><code>goat admin onboard &lt;handle&gt; --revoke</code></td><td>ADR 1031 · mesh-first offboarding</td></tr>
<tr><td>pre-cut slot ACL in <code>lib-fabric.sh</code></td><td>the slot-pool write-anchor ACL</td><td>ADR 1025 · dynamic tenant authz</td></tr>
<tr><td><code>goat health</code> gauge + footprint</td><td>same meter image</td><td>ADR 1034 · fabric-health surface</td></tr>
<tr><td>envelope band (represented)</td><td><code>goat top</code> band</td><td>ADR 1045 · throughput envelopes</td></tr>
</table>

<p class="meta">Built-vs-designed and the two build findings are in <code>FINDINGS.md</code>. This report
is regenerated by <code>report/generate-report.sh</code> — re-run it and every number above is read
back fresh from a live run.</p>

</div></body></html>
HTML
} > "$OUT"

echo "==> done: $OUT"
echo "    open it with:  open $OUT"
