#!/usr/bin/env python3
"""Compares occprobe's expected clip timeline with the app's maskTrace log.

Usage: mask_lag.py <probe.txt> <applog.txt>

Both are step functions of the hole set of the clipped cover. Reports the
episodes where they disagree, their total and longest duration, and the
disagreement integrated as px*ms (4 px grid), split into paper drawn OVER
another window (a hole not yet cut) and paper MISSING (a stale hole)."""
import re
import sys


def cells(spec, g=4):
    out = set()
    for part in filter(None, spec.split(';')):
        x, y, w, h = map(int, part.split(','))
        for i in range(x // g, (x + w) // g):
            for j in range(y // g, (y + h) // g):
                out.add((i, j))
    return out


probe, app = [], []
for line in open(sys.argv[1]):
    m = re.match(r'probe t=([\d.]+) holes=(\S*)', line.strip())
    if m:
        probe.append((float(m.group(1)), 'p', cells(m.group(2))))
for line in open(sys.argv[2]):
    m = re.search(r'mask t=([\d.]+) wid=\d+ holes=(\S*)', line)
    if m:
        app.append((float(m.group(1)), 'a', cells(m.group(2))))
if not probe:
    sys.exit('no probe samples')
t0, t_end = probe[0][0], probe[-1][0] + 0.2
got = set()
for t, _, c in app:
    if t < t0:
        got = c
events = sorted([e for e in probe + app if t0 <= e[0] <= t_end], key=lambda e: e[0])
exp = None
over = missing = bad_ms = longest = 0.0
episodes, bad_since, prev = 0, None, None
for t, kind, c in events:
    if prev is not None and exp is not None and exp != got:
        dt = (t - prev) * 1000
        bad_ms += dt
        over += len(exp - got) * 16 * dt
        missing += len(got - exp) * 16 * dt
    if kind == 'p':
        exp = c
    else:
        got = c
    prev = t
    if exp is not None:
        if exp != got and bad_since is None:
            bad_since, episodes = t, episodes + 1
        elif exp == got and bad_since is not None:
            longest = max(longest, t - bad_since)
            bad_since = None
print(f"mismatch_episodes={episodes} mismatch_ms={bad_ms:.0f} longest_ms={longest * 1000:.0f} "
      f"paper_over_other_px_ms={over:.0f} paper_missing_px_ms={missing:.0f} app_updates={len(app)}")
