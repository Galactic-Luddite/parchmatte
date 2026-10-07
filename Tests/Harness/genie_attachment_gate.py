#!/usr/bin/env python3
"""Reject visibly detached Ribbon probes; never promote a vertex-only check.

Input is a JSON array of diagnostic records with video time `t` (seconds),
material alpha factor `alpha` (0..0.6), and integer `outside`: on-screen
owned-material body vertices outside the owned fixture silhouette expanded
by two logical points. Off-screen vertices must be excluded by the probe.
The caller must validate pixel/point conversion, capture cadence, time
correlation and silhouette annotations before supplying observations.
No target pixels or metadata are read by this analyzer or by product code.

An empty/invalid recording is an input error, not a failed motion design.
Vertex sampling can demonstrate geometric spill, but cannot prove complete
triangle containment, actual ink coverage, good pacing or natural appearance.
Therefore there is no PASS
verdict: even zero observed spill remains INCONCLUSIVE for app acceptance.
Exit statuses: 1 REJECTED, 2 invalid input, 3 INCONCLUSIVE. No success status.
"""

import argparse
import json
import math
from pathlib import Path


def assess(frames):
    if not frames:
        raise ValueError("no observations")
    previous = None
    pairs = 0
    visible_spill = 0
    for frame in frames:
        time, alpha, outside = frame["t"], frame["alpha"], frame["outside"]
        if (isinstance(time, bool) or not isinstance(time, (int, float))
                or not math.isfinite(time) or time < 0
                or isinstance(alpha, bool) or not isinstance(alpha, (int, float))
                or not math.isfinite(alpha) or not 0 <= alpha <= 0.6
                or isinstance(outside, bool) or not isinstance(outside, int)
                or outside < 0):
            raise ValueError("invalid observation")
        if previous is not None and time <= previous[0]:
            raise ValueError("frame times must increase")
        # Ignore only zero-alpha material. Low but nonzero alpha still counts.
        spill = alpha > 0 and outside > 0
        visible_spill += int(spill)
        if previous is not None and time - previous[0] <= 0.0334:
            pairs += int(spill and previous[1])
        previous = (time, spill)
    return {"verdict": "REJECTED" if pairs else "INCONCLUSIVE",
            "observations": len(frames), "visible_spill_frames": visible_spill,
            "consecutive_spill_pairs": pairs,
            "limitation": "Vertex probes can reject attachment, never prove it."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("observations", type=Path)
    args = parser.parse_args()
    try:
        result = assess(json.loads(args.observations.read_text()))
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(2, f"Invalid diagnostic evidence: {error}\n")
    print(json.dumps(result, indent=2))
    return 1 if result["verdict"] == "REJECTED" else 3


if __name__ == "__main__":
    raise SystemExit(main())
