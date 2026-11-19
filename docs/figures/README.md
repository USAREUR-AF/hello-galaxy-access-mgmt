# Figures

`make-figures.py` draws the figure at the top of the root README, `slot-pool`, in a
light and a dark version for a `<picture>` element. Its facts come from
the slot pool in `local-fabric/lib-fabric.sh` (anchors and holders) and the assertions of scenarios 02 and 04 (what rotate and revoke do); the build stops if one of them is no longer there.

```
python3 -I docs/figures/make-figures.py           # write the SVG files
python3 -I docs/figures/make-figures.py --check   # exit 1 if a committed SVG is out of date
```

Standard library only. The SVG files are self-contained: no external fonts,
styles or images.
