#!/usr/bin/env bash
# Same-app window switching: two TextEdit windows, the larger (A) covered.
# Focus goes between A and B N times, by clicking (mode click) or with ⌘`
# (mode cycle), while actprobe watches A's cover. Whole-screen paper is off
# for the run and restored after. Only this test's cover is removed.
# Mode occlude instead moves B across A in steps (from rest), N steps.
# With OCC=1, occprobe also records the expected clip timeline for
# mask_lag.py (clipped-cover experiment) in $PM_TMP/pm/<tag>.occ.
# Usage: Tests/Harness/samewin_run.sh click|cycle|occlude [rounds] [tag]
set -uo pipefail
source "$(dirname "$0")/lib.sh"
MODE=${1:-click}
ROUNDS=${2:-20}
TAG=${3:-samewin-$MODE}
mkdir -p $PM_TMP/pm
[ -x "$BIN/actprobe" ] && [ "$BIN/actprobe" -nt "$HARNESS/actprobe.swift" ] || swiftc -O "$HARNESS/actprobe.swift" -o "$BIN/actprobe"
[ -x "$BIN/occprobe" ] && [ "$BIN/occprobe" -nt "$HARNESS/occprobe.swift" ] || swiftc -O "$HARNESS/occprobe.swift" -o "$BIN/occprobe"
[ -x "$BIN/click" ] && [ "$BIN/click" -nt "$HARNESS/click.swift" ] || swiftc -O "$HARNESS/click.swift" -o "$BIN/click"
was_whole=$(whole_screen && echo on || echo off)
set_whole_screen off
ensure_textedit
open_textedit_window "A" 200 150 1000 750
cover_front
open_textedit_window "B" 700 500 1300 900
"$BIN/check_cover" TextEdit
SECS=$(echo "$ROUNDS * 1.2 + 1" | bc)
[ "$MODE" = occlude ] && sleep 2   # start from the idle rate
"$BIN/actprobe" TextEdit "$SECS" --timeline > "$PM_TMP/pm/$TAG.txt" &
[ "${OCC:-0}" = 1 ] && "$BIN/occprobe" TextEdit "$SECS" > "$PM_TMP/pm/$TAG.occ" &
sleep 0.5
for r in $(seq 1 "$ROUNDS"); do
    if [ "$MODE" = occlude ]; then
        x=$((100 + (r % 40) * 25))
        textedit "set bounds of window 1 to {$x, 500, $((x + 600)), 900}" >/dev/null
    elif [ "$MODE" = click ]; then
        "$BIN/click" 300 250; sleep 0.5      # A (outside B)
        "$BIN/click" 1200 850; sleep 0.5     # B (outside A)
    else
        osascript -e 'tell application "System Events" to keystroke "`" using command down'; sleep 0.5
    fi
done
wait
cat "$PM_TMP/pm/$TAG.txt"
"$BIN/click" 300 250; sleep 0.4
hotkey 35; sleep 0.5   # remove only this test's cover (A is front)
textedit_reset
osascript -e 'tell application "TextEdit" to quit saving no' >/dev/null 2>&1
set_whole_screen "$was_whole"
