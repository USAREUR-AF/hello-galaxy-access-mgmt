"""Draw the README figure from the slot pool and the scenarios that use it.

    python3 -I docs/figures/make-figures.py           # write docs/figures/*.svg
    python3 -I docs/figures/make-figures.py --check   # exit 1 if a committed figure is out of date

Each figure is written twice, `<name>-light.svg` and `<name>-dark.svg`, for a
`<picture>` element. The slots and their holders are read from
local-fabric/lib-fabric.sh; what the figure says happens to them is checked
against the scenario assertions, and the build stops if one is no longer there.
Standard library only; the output is deterministic.
"""

import os
import re
import sys
from xml.sax.saxutils import escape

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))

THEMES = {
    "light": {
        "paper": "#ffffff", "panel": "#f6f8fa", "ink": "#1f2328", "quiet": "#59636e", "rule": "#d1d9e0",
        "line": "#818b98", "accent": "#0969da", "accent_soft": "#ddf4ff", "on_accent": "#ffffff",
        "good": "#1a7f37", "good_bg": "#dafbe1", "crit": "#cf222e", "crit_bg": "#ffebe9",
        "warn": "#9a6700", "warn_bg": "#fff8c5", "mute": "#6e7781",
    },
    "dark": {
        "paper": "#0d1117", "panel": "#161b22", "ink": "#e6edf3", "quiet": "#9198a1", "rule": "#3d444d",
        "line": "#7d8590", "accent": "#4493f8", "accent_soft": "#132c4c", "on_accent": "#0d1117",
        "good": "#3fb950", "good_bg": "#12261e", "crit": "#f85149", "crit_bg": "#2f1517",
        "warn": "#d29922", "warn_bg": "#2e2510", "mute": "#8b949e",
    },
}
SANS = "-apple-system, BlinkMacSystemFont, 'Segoe UI', 'Noto Sans', Helvetica, Arial, sans-serif"
MONO = "ui-monospace, SFMono-Regular, 'SF Mono', Menlo, Consolas, 'Liberation Mono', monospace"
W = 880          # every figure's width; a README column shows it at about 830 px
KIND = {"plain": ("panel", "rule"), "accent": ("accent_soft", "accent"), "good": ("good_bg", "good"),
        "crit": ("crit_bg", "crit"), "warn": ("warn_bg", "warn")}


def n(v):
    return ("%.1f" % v).rstrip("0").rstrip(".")


def tw(s, size, mono=False, bold=False):
    """Text width estimate; the browser lint confirms it."""
    if mono:
        return len(s) * size * 0.61
    w = 0.0
    for c in s:
        if c in "il.,:;|!'`·1 ":
            w += 0.30
        elif c in "ft()[]/-":
            w += 0.36
        elif c in "mwMW@%":
            w += 0.86
        elif c.isupper() or c in "0123456789≤≥²→":
            w += 0.64
        else:
            w += 0.55
    return w * size * (1.06 if bold else 1.0)


def wrap(s, width, size, mono=False, bold=False):
    out, line = [], ""
    for word in s.split(" "):
        t = word if not line else line + " " + word
        if tw(t, size, mono, bold) <= width or not line:
            line = t
        else:
            out.append(line)
            line = word
    if line:
        out.append(line)
    return out


class SVG:
    def __init__(self, w, h, title, desc):
        self.w, self.h, self.title, self.desc = w, h, title, desc
        self.items = []

    def add(self, s):
        self.items.append(s)

    def rect(self, x, y, w, h, fill="panel", stroke="rule", rx=8, sw=1, dash=None):
        d = ' stroke-dasharray="%s"' % dash if dash else ""
        self.add('<rect x="%s" y="%s" width="%s" height="%s" rx="%s" fill="{%s}" stroke="{%s}" stroke-width="%s"%s/>'
                 % (n(x), n(y), n(w), n(h), n(rx), fill, stroke, n(sw), d))

    def text(self, x, y, s, size=14, fill="ink", anchor="start", bold=False, mono=False):
        self.add('<text x="%s" y="%s" font-size="%s" fill="{%s}" text-anchor="%s"%s%s>%s</text>'
                 % (n(x), n(y), n(size), fill, anchor, ' font-weight="600"' if bold else "",
                    ' font-family="%s"' % MONO if mono else "", escape(s)))

    def line(self, x1, y1, x2, y2, stroke="line", sw=1.5, dash=None, arrow=False):
        d = ' stroke-dasharray="%s"' % dash if dash else ""
        m = ' marker-end="url(#arrow-%s)"' % stroke if arrow else ""
        self.add('<line x1="%s" y1="%s" x2="%s" y2="%s" stroke="{%s}" stroke-width="%s"%s%s/>'
                 % (n(x1), n(y1), n(x2), n(y2), stroke, n(sw), d, m))

    def box(self, x, y, w, h, title, rows=(), kind="plain", dash=None, size=14, mono_rows=(), title_fill="ink"):
        """A box with a bold title and wrapped rows; rows whose index is in mono_rows are set in mono."""
        fill, stroke = KIND[kind]
        self.rect(x, y, w, h, fill=fill, stroke=stroke, sw=1.5, dash=dash)
        self.text(x + 14, y + 26, title, 15, bold=True, fill=title_fill)
        yy = y + 50
        for i, r in enumerate(rows):
            mono = i in mono_rows
            fill_r = "ink"
            if isinstance(r, tuple):
                r, fill_r = r
            for ln in wrap(r, w - 28, size if not mono else 13, mono=mono):
                self.text(x + 14, yy, ln, size if not mono else 13, fill=fill_r, mono=mono)
                yy += 20
        return yy

    def render(self, theme):
        t = THEMES[theme]
        body = "\n".join(self.items)
        for k, v in t.items():
            body = body.replace("{%s}" % k, v)
        markers = "".join(
            '<marker id="arrow-%s" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" '
            'orient="auto-start-reverse"><path d="M0,0L10,5L0,10z" fill="%s"/></marker>' % (k, t[k])
            for k in ("line", "accent", "good", "crit"))
        return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d" role="img" '
                'aria-labelledby="t d" font-family="%s">\n<title id="t">%s</title>\n<desc id="d">%s</desc>\n'
                '<defs>%s</defs>\n<rect width="100%%" height="100%%" rx="12" fill="%s"/>\n%s\n</svg>\n'
                % (self.w, self.h, self.w, self.h, SANS.replace("'", "&apos;"), escape(self.title),
                   escape(self.desc), markers, t["paper"], body))


def header(f, title, sub):
    f.text(24, 38, title, 20, bold=True)
    f.text(24, 62, sub, 14, fill="quiet")


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as fh:
        return fh.read()


def need(rel, *needles):
    """Fail the build if a fact the figure prints is no longer in the file it comes from."""
    text = read(rel)
    missing = [s for s in needles if s not in text]
    if missing:
        sys.exit("make-figures: %s no longer contains %s; update the figure" % (rel, ", ".join(map(repr, missing))))


def main(figures, argv):
    check = "--check" in argv
    stale = []
    for name, fn in figures:
        fig = fn()
        for theme in THEMES:
            p = os.path.join(HERE, "%s-%s.svg" % (name, theme))
            out = fig.render(theme)
            if check:
                if not os.path.isfile(p) or open(p, encoding="utf-8").read() != out:
                    stale.append(os.path.relpath(p, ROOT))
            else:
                with open(p, "w", encoding="utf-8") as fh:
                    fh.write(out)
                print(os.path.relpath(p, ROOT))
    if stale:
        print("out of date: " + ", ".join(stale) + "; run python3 -I docs/figures/make-figures.py", file=sys.stderr)
        return 1
    return 0


# ---------------------------------------------------------------- the hero
POOL = "local-fabric/lib-fabric.sh"
ROTATE = "scenarios/02-rotate-live-actor/run.sh"
REVOKE = "scenarios/04-revoke-the-spammer/run.sh"


def slots():
    """(holder, anchor prefix) for each pre-cut slot, in the order lib-fabric.sh declares them."""
    text = read(POOL)
    out = []
    for m in re.finditer(r'^FAB_ANCHOR_\w+="\$\(pad8 ([0-9a-f]{8})\)"\s+# (\S+)', text, re.M):
        out.append((m.group(2), m.group(1)))
    if len(out) != 4:
        sys.exit("make-figures: expected four pre-cut slots in %s, found %d" % (POOL, len(out)))
    return out


def fig_slot_pool():
    need(ROTATE, "the router ACL was untouched", "actor still publishing after rotation")
    need(REVOKE, "the cut DENIED the offender's writes", "the situational lane recovered")
    pool = slots()
    title = "Rotate keeps the slot; revoke removes it"
    outcome = {
        "weather-vane": ("accent", "accent", None,
                         "rotated: a fresh leaf, the same anchor; the access list is unchanged and it keeps publishing"),
        "steady-eddie": ("plain", "quiet", None, "control producer: publishes throughout"),
        "loud-mouth": ("crit", "crit", None,
                       "revoked: its grant is removed; its writes are denied and the fabric recovers"),
        "(unallocated)": ("plain", "quiet", "5 4", "free: already authorized, waiting for a holder"),
    }
    f = SVG(W, 448, title,
            "The local Zenoh router's access list is static and default-deny, with four slots cut into it before "
            "anyone joins, each a write grant keyed on a certificate common name equal to the slot's anchor. "
            "weather-vane is rotated to a fresh leaf with the same anchor, so the access list does not change and "
            "it keeps publishing; loud-mouth is revoked by removing its slot's grant, so its writes are denied; "
            "steady-eddie publishes throughout; the fourth slot is free.")
    header(f, title, "The router's access list is static. Its grants follow a slot anchor, never a certificate.")
    px, py, pw = 24, 84, W - 48
    f.rect(px, py, pw, 304, fill="paper", stroke="line", sw=1.5, rx=10)
    f.text(px + 18, py + 28, "Zenoh router: default-deny access list, four slots cut in before anyone joins", 15,
           bold=True)
    hx = [px + 18, px + 132, px + 286, px + 418]
    for x, h in zip(hx, ["slot anchor", "write grant", "holder", "what the scenarios do to it"]):
        f.text(x, py + 56, h, 13, fill="quiet")
    y = py + 68
    for holder, pre in pool:
        kind, tone, dash, note = outcome[holder]
        fill, stroke = KIND[kind]
        f.rect(px + 10, y, pw - 20, 50, fill=fill, stroke=stroke, sw=1.5, rx=6, dash=dash)
        f.text(hx[0], y + 30, pre + "…", 14, mono=True, bold=True)
        f.text(hx[1], y + 30, "put %s…/**" % pre, 13, mono=True)
        f.text(hx[2], y + 30, "free" if holder.startswith("(") else holder, 14, bold=True,
               fill="quiet" if holder.startswith("(") else "ink")
        rows = wrap(note, pw - 20 - (hx[3] - px) + 10 - 14, 14)
        for i, r in enumerate(rows):
            f.text(hx[3], y + 30 - 9 * (len(rows) - 1) + 18 * i, r, 14, fill=tone if tone != "quiet" else "ink")
        y += 58
    f.text(24, 418, "A leaf certificate may write when its common name equals a granted slot's anchor.", 14,
           fill="quiet")
    f.text(24, 438, "Run it yourself: local-fabric/up.sh, then bin/access-mgmt all --env local", 14, fill="quiet")
    return f


if __name__ == "__main__":
    sys.exit(main([("slot-pool", fig_slot_pool)], sys.argv[1:]))
