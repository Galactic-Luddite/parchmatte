#!/usr/bin/env bash
# Tab-follow adoption must never put two covers on one window (review C2).
# Three TextEdit windows share one frame; the front two are covered. Both
# covered windows vanish at once (closed together), leaving the uncovered
# third in the same place. Each missing cover may follow a same-frame
# sibling, but no two may claim the same one: at most one cover may end up
# on screen, so the composite stays within the 60% single-panel cap.
#
# Only touches covers it creates (on its own TextEdit windows).
# Usage: Tests/Harness/scenarios_adopt.sh
set -uo pipefail
source "$(dirname "$0")/lib.sh"

was_whole=$(whole_screen && echo on || echo off)
set_whole_screen off
ensure_textedit

open_textedit_window "C" 300 200 1100 800
open_textedit_window "B" 300 200 1100 800
cover_front                                   # covers B
open_textedit_window "A" 300 200 1100 800
cover_front                                   # covers A
expect "D1 two covers placed" bash -c "\"$BIN/covers\" TextEdit | grep -q '^windowCovers=2$' && echo 2 covers"

# Close both covered windows in one go; C stays where they were.
textedit 'set a to id of window 1
set b to id of window 2
close window id a saving no
close window id b saving no' >/dev/null 2>&1
sleep 2
count() { "$BIN/covers" TextEdit | sed -n 's/^windowCovers=//p'; }
n=$(count)
# Worst case for n stacked panels, each capped at 0.6: 1 - 0.4^n.
composite=$(python3 -c "print(round(1 - 0.4 ** $n, 3))")
expect "D2 at most one cover on the sibling (covers=$n)" test "$n" -le 1
expect "D3 composite <= 0.6 (worst case $composite)" python3 -c "import sys; sys.exit(0 if $composite <= 0.6 else 1)"

textedit_reset; sleep 4
osascript -e 'tell application "TextEdit" to quit saving no' >/dev/null 2>&1
set_whole_screen "$was_whole"
echo "adopt: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
