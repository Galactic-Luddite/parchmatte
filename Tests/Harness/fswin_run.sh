#!/usr/bin/env bash
# Measures a WINDOW cover through native full-screen enter and exit
# (ctrl-cmd-F) on a TextEdit window, N rounds, with fswin. Whole-screen paper
# is switched off for the run and restored after.
# Usage: Tests/Harness/fswin_run.sh [rounds] [tag]
set -uo pipefail
source "$(dirname "$0")/lib.sh"
ROUNDS=${1:-2}
TAG=${2:-run}
mkdir -p $PM_TMP/pm
[ -x "$BIN/fswin" ] && [ "$BIN/fswin" -nt "$HARNESS/fswin.swift" ] || swiftc -O "$HARNESS/fswin.swift" -o "$BIN/fswin"
was_whole=$(whole_screen && echo on || echo off)
set_whole_screen off
ensure_textedit
open_textedit_window "FSW" 200 150 1000 750
cover_front
"$BIN/check_cover" TextEdit
for r in $(seq 1 "$ROUNDS"); do
    bring_front TextEdit
    "$BIN/fswin" TextEdit 3.5 --timeline > "$PM_TMP/pm/$TAG-enter$r.txt" &
    sleep 0.3
    osascript -e 'tell application "System Events" to keystroke "f" using {control down, command down}'
    wait
    echo "enter $r: $(tail -1 $PM_TMP/pm/$TAG-enter$r.txt)"
    "$BIN/fswin" TextEdit 3.5 --timeline > "$PM_TMP/pm/$TAG-exit$r.txt" &
    sleep 0.3
    osascript -e 'tell application "System Events" to keystroke "f" using {control down, command down}'
    wait
    echo "exit  $r: $(tail -1 $PM_TMP/pm/$TAG-exit$r.txt)"
done
"$BIN/check_cover" TextEdit
bring_front TextEdit; hotkey 35; sleep 0.5   # remove only this test's cover
textedit_reset
osascript -e 'tell application "TextEdit" to quit saving no' >/dev/null 2>&1
set_whole_screen "$was_whole"
