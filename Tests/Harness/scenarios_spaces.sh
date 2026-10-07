#!/usr/bin/env bash
# Desktop (Space) scenarios (B1, B7): swipe away from a covered window and
# back, measuring uncovered/misaligned frames; and whole-screen covers staying
# one-per-display across repeated swipes. Needs at least two desktops on the
# main display. Leaves Paper Whole Screen as found.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

swipe() {  # swipe right|left
    local code=124; [ "$1" = left ] && code=123
    osascript -e "tell application \"System Events\" to key code $code using {control down}"
}
covers_on_main() { "$BIN/screencovers" 0.2 | head -1 | grep -o '"0,0 [0-9]*x[0-9]*"' | wc -l | tr -d ' '; }

was_whole=$(whole_screen && echo on || echo off)

# Window cover rides the swipe.
set_whole_screen off
ensure_textedit
open_textedit_window "S" 200 150 1000 750
cover_front
"$BIN/probe" TextEdit 7 > $PM_TMP/parchmatte-spaces.txt &
probe=$!
sleep 1; swipe right; sleep 2.5; swipe left
wait "$probe"
result="$(cat $PM_TMP/parchmatte-spaces.txt)"; rm -f $PM_TMP/parchmatte-spaces.txt
uncovered=$(echo "$result" | sed -E 's/.*uncovered=([0-9]+).*/\1/')
expect "B1 window cover rides swipe ($result)" test "$uncovered" -eq 0
expect "B1 cover still aligned after swipe" "$BIN/check_cover" TextEdit
textedit_reset
osascript -e 'tell application "TextEdit" to quit saving no' >/dev/null 2>&1

# Whole screen: after several swipes there is exactly one cover on the main
# display's active desktop (no duplicates, no gaps).
set_whole_screen on
for i in 1 2 3; do swipe right; sleep 1.8; swipe left; sleep 1.8; done
sleep 1
expect "B1 one whole-screen cover on main display after swipes" test "$(covers_on_main)" -eq 1

set_whole_screen "$was_whole"
echo "spaces: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
