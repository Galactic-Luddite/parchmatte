#!/usr/bin/env python3
"""Summarises a probe --timeline from motion_run.sh: for each change, the
distance between the target window and the nearest cover, and how long the
target sat on screen with no unfaded cover over it.
Usage: motion_lag.py <timeline.txt>..."""
import os
import re
import sys
SIZE = os.environ.get("SIZE")  # e.g. 800x600: follow only that window
R = re.compile(r'"(-?\d+),(-?\d+) (\d+)x(\d+)( faded)?"')
for path in sys.argv[1:]:
    rows = []
    for line in open(path):
        m = re.match(r'\s*([\d.]+) target=\[(.*?)\] covers=\[(.*)\]', line)
        if not m: continue
        t = float(m.group(1)); tg = [g for g in R.findall(m.group(2)) if not SIZE or f"{g[2]}x{g[3]}" == SIZE]; cv = [c for c in R.findall(m.group(3)) if not c[4]]
        rows.append((t, tg[0] if tg else None, cv))
    errs, bare, bare_start = [], 0.0, None
    for i, (t, tg, cv) in enumerate(rows):
        nxt = rows[i + 1][0] if i + 1 < len(rows) else t
        if tg is None: continue
        x, y, w, h = map(int, tg[:4])
        near = [c for c in cv if int(c[2]) == w]
        if near:
            errs.append(min(abs(int(c[0]) - x) + abs(int(c[1]) - y) for c in near))
        else:
            bare += nxt - t
    mv = [e for e in errs if e > 0]
    mean = sum(errs) / max(1, len(errs))
    # Jitter: how unevenly the cover trails. A steady one-frame lag reads
    # as a smooth offset; a lag swinging between 0 and 2 frames stutters.
    jitter = (sum((e - mean) ** 2 for e in errs) / max(1, len(errs))) ** 0.5
    print(f"{path}: changes={len(rows)} lagging={len(mv)}/{len(errs)} "
          f"meanErr={mean:.1f}px jitter={jitter:.1f}px maxErr={max(errs, default=0)}px uncoveredSec={bare:.3f}")
