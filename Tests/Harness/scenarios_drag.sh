#!/usr/bin/env bash
# Drag test (C1): moves a covered TextEdit window in steps, starting from
# rest (so the tracker begins at its idle rate), while the probe measures
# misaligned frames and the worst offset. Leaves Paper Whole Screen as found.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

was_whole=$(whole_screen && echo on || echo off)
set_whole_screen off
ensure_textedit
open_textedit_window "D" 200 150 900 650
cover_front
sleep 2   # let the tracker settle to its idle rate

"$BIN/probe" TextEdit 6 ${TIMELINE:-} > $PM_TMP/parchmatte-drag.txt &
probe=$!
sleep 0.5
for step in $(seq 1 40); do
    x=$((200 + (step % 20) * 25))
    textedit "set bounds of window 1 to {$x, 150, $((x + 700)), 650}"
done
wait "$probe"
result=$(cat $PM_TMP/parchmatte-drag.txt)
rm -f $PM_TMP/parchmatte-drag.txt
echo "drag: $result"
# The cover may trail a moving window by a frame (misaligned), but must
# never leave it uncovered.
expect "C1d never uncovered while dragged" bash -c "grep -q ' uncovered=0 ' <<< \"\$0\" && grep -Eq 'samples=[1-9]' <<< \"\$0\"" "$result"

textedit_reset
osascript -e 'tell application "TextEdit" to quit saving no' >/dev/null 2>&1
set_whole_screen "$was_whole"
echo "drag: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
