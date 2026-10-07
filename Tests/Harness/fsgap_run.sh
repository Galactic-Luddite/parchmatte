#!/usr/bin/env bash
# Measures the whole-screen paper gap across TextEdit full-screen enter and
# exit (ctrl-cmd-F), N rounds. Requires Paper Whole Screen on.
# Usage: Tests/Harness/fsgap_run.sh [rounds]
set -uo pipefail
source "$(dirname "$0")/lib.sh"
ROUNDS=${1:-2}
[ -x "$BIN/fsgap" ] && [ "$BIN/fsgap" -nt "$HARNESS/fsgap.swift" ] || swiftc -O "$HARNESS/fsgap.swift" -o "$BIN/fsgap"
whole_screen || { echo "whole screen is off; skipping"; exit 1; }
ensure_textedit
open_textedit_window "FS" 200 150 1000 750
for r in $(seq 1 "$ROUNDS"); do
    bring_front TextEdit
    "$BIN/fsgap" 3.5 --timeline > "$PM_TMP/pm/enter$r.txt" &
    sleep 0.3
    osascript -e 'tell application "System Events" to keystroke "f" using {control down, command down}'
    wait
    echo "enter $r: $(tail -1 $PM_TMP/pm/enter$r.txt)"
    "$BIN/fsgap" 3.5 --timeline > "$PM_TMP/pm/exit$r.txt" &
    sleep 0.3
    osascript -e 'tell application "System Events" to keystroke "f" using {control down, command down}'
    wait
    echo "exit  $r: $(tail -1 $PM_TMP/pm/exit$r.txt)"
done
textedit_reset
osascript -e 'tell application "TextEdit" to quit saving no' >/dev/null 2>&1
