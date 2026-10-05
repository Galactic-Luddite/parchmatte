#!/usr/bin/env bash
# Sibling raise: two TextEdit windows, the larger (A) covered. Each round
# brings Finder forward, clicks A (activating TextEdit, which lifts A's
# cover one level up), waits a random 0.8-1.4 s, then clicks B. B comes to
# the front of the normal level, under the lifted cover; sibprobe times how
# long the cover stays above B (issue #37). Whole-screen paper is off for
# the run and restored after. Only this test's cover is removed.
# Passes when no stale cover outlasts MAX_MS (default 50).
# Usage: Tests/Harness/sibling_run.sh [rounds] [tag]
set -uo pipefail
source "$(dirname "$0")/lib.sh"
ROUNDS=${1:-20}
TAG=${2:-sibling}
MAX_MS=${MAX_MS:-50}
OUT="$HARNESS/results"
mkdir -p "$OUT" "$BIN"
for t in activate_app check_cover covers click sibprobe; do
    [ -x "$BIN/$t" ] && [ "$BIN/$t" -nt "$HARNESS/$t.swift" ] || swiftc -O "$HARNESS/$t.swift" -o "$BIN/$t" || exit 2
done
was_whole=$(whole_screen && echo on || echo off)
set_whole_screen off
ensure_textedit
# A cover left by a closed document lingers 3 s and would re-attach to a
# new window in the same place, which the hotkey would then toggle off.
sleep 3.5
open_textedit_window "A" 200 150 1000 750
cover_front
open_textedit_window "B" 700 500 1300 900
"$BIN/click" 300 250; sleep 1
SECS=$(echo "$ROUNDS * 3.8 + 2" | bc)
"$BIN/sibprobe" TextEdit "$SECS" --timeline > "$OUT/$TAG.txt" &
probe=$!
sleep 0.5
for r in $(seq 1 "$ROUNDS"); do
    osascript -e 'tell application "Finder" to activate' >/dev/null; sleep 0.7
    "$BIN/click" 300 250                 # A (outside B), activating TextEdit
    sleep "$(awk -v s=$RANDOM 'BEGIN { printf "%.3f", 0.8 + (s % 600) / 1000 }')"
    "$BIN/click" 1200 850                # B (outside A), same app
    sleep 1
done
wait "$probe"
tail -1 "$OUT/$TAG.txt"
"$BIN/click" 300 250; sleep 0.4
hotkey 35; sleep 0.5   # remove only this test's cover (A is front)
textedit_reset
osascript -e 'tell application "TextEdit" to quit saving no' >/dev/null 2>&1
set_whole_screen "$was_whole"
max=$(tail -1 "$OUT/$TAG.txt" | sed -n 's/.*max \([0-9]*\) ms.*/\1/p')
raises=$(tail -1 "$OUT/$TAG.txt" | sed -n 's/^sibling raises \([0-9]*\),.*/\1/p')
[ -n "$max" ] && [ "${raises:-0}" -ge "$ROUNDS" ] && [ "$max" -le "$MAX_MS" ]
