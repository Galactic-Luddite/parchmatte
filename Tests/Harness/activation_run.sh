#!/usr/bin/env bash
# Measures a WINDOW cover while focus goes away from the covered TextEdit
# window and comes back, N rounds, with actprobe. Half the returns are
# LaunchServices activations (open -a), half real clicks on the window.
# Whole-screen paper is switched off for the run and restored after. Only
# this test's cover is removed at the end.
# OCC=1 also runs occprobe (see samewin_run.sh).
# Usage: Tests/Harness/activation_run.sh [rounds] [tag]
set -uo pipefail
source "$(dirname "$0")/lib.sh"
ROUNDS=${1:-20}
TAG=${2:-act}
mkdir -p $PM_TMP/pm
[ -x "$BIN/actprobe" ] && [ "$BIN/actprobe" -nt "$HARNESS/actprobe.swift" ] || swiftc -O "$HARNESS/actprobe.swift" -o "$BIN/actprobe"
[ -x "$BIN/click" ] && [ "$BIN/click" -nt "$HARNESS/click.swift" ] || swiftc -O "$HARNESS/click.swift" -o "$BIN/click"
was_whole=$(whole_screen && echo on || echo off)
set_whole_screen off
ensure_textedit
open_textedit_window "ACT" 200 150 1000 750
cover_front
"$BIN/check_cover" TextEdit
SECS=$(echo "$ROUNDS * 1.6 + 1" | bc)
"$BIN/actprobe" TextEdit "$SECS" --timeline > "$PM_TMP/pm/$TAG.txt" &
[ "${OCC:-0}" = 1 ] && "$BIN/occprobe" TextEdit "$SECS" > "$PM_TMP/pm/$TAG.occ" &
sleep 0.5
for r in $(seq 1 "$ROUNDS"); do
    open -a Finder; sleep 0.7
    if [ $((r % 2)) = 0 ]; then "$BIN/click" 600 450; else open -a TextEdit; fi
    sleep 0.7
done
wait
cat "$PM_TMP/pm/$TAG.txt"
bring_front TextEdit; hotkey 35; sleep 0.5   # remove only this test's cover
textedit_reset
osascript -e 'tell application "TextEdit" to quit saving no' >/dev/null 2>&1
set_whole_screen "$was_whole"
