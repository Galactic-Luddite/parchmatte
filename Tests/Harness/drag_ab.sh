#!/usr/bin/env bash
# Drag-lag A/B between app bundles: launches each bundle in turn, runs the
# drag phases of motion_run.sh, and prints motion_lag.py summaries labelled
# by the bundle's grandparent directory (dist/Parchmatte.app under b-v2 is
# "b-v2"). Rounds interleave the bundles so load drift on the host cancels
# out. The app that was running is relaunched at the end.
# Usage: [PROBE_FLAGS=--vsync] drag_ab.sh <rounds> <app bundle>...
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PM_TMP="${TMPDIR:-/tmp}"; PM_TMP="${PM_TMP%/}"
ROUNDS=$1; shift
OUT=${OUT:-$PM_TMP/pm-dragab}; mkdir -p "$OUT"
restore=$(ps -o args= -p "$(pgrep -x Parchmatte | head -1)" 2>/dev/null | sed 's|/Contents/MacOS/Parchmatte.*||')
label() { basename "$(dirname "$(dirname "$1")")"; }
relaunch() {
    osascript -e 'tell application id "com.galacticluddite.parchmatte" to quit' >/dev/null 2>&1; sleep 1
    pkill -x Parchmatte 2>/dev/null; sleep 1
    open -n "$1"
    sleep 4
}
for r in $(seq 1 "$ROUNDS"); do for app in "$@"; do
    name=$(label "$app")
    relaunch "$app"
    echo "== $name round $r"
    PHASES="${PHASES:-drag slow fastdrag tile}" "$HERE/motion_run.sh" "$OUT/$name-$r" | grep -v "^PASS"
    python3 "$HERE/motion_lag.py" "$OUT/$name-$r"/*.txt | sed "s|$OUT/||"
done; done
pkill -x Parchmatte 2>/dev/null; sleep 1
[ -n "$restore" ] && open "$restore"
