#!/usr/bin/env bash
# Native full-screen scenarios (B2) with TextEdit: a window cover must follow
# the window into and out of full screen, and whole-screen paper must cover a
# full-screen Space. Leaves Paper Whole Screen as found.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

fullscreen() {  # fullscreen true|false
    osascript -e "tell application \"System Events\" to tell process \"TextEdit\" to set value of attribute \"AXFullScreen\" of window 1 to $1"
    sleep 2.5   # the full-screen animation plus the cover's settle time
}
# Whole-screen covers on the main display's active Space (x = 0, y = 0).
main_screen_covered() {
    local line; line="$("$BIN/screencovers" 0.2 | head -1)"
    if echo "$line" | grep -q '"0,0 '; then echo "PASS $line"; return 0; fi
    echo "FAIL $line"; return 1
}

was_whole=$(whole_screen && echo on || echo off)

# Window cover through full screen.
set_whole_screen off
ensure_textedit
open_textedit_window "F" 200 150 1000 750
cover_front
expect "B2 window cover before full screen" "$BIN/check_cover" TextEdit
fullscreen true
expect "B2 window cover in full screen" "$BIN/check_cover" TextEdit
fullscreen false
expect "B2 window cover after full screen" "$BIN/check_cover" TextEdit

# Whole-screen paper on a full-screen Space.
set_whole_screen on
fullscreen true
expect "B2 whole screen on full-screen Space" main_screen_covered
fullscreen false
expect "B2 whole screen after leaving full screen" main_screen_covered

textedit_reset
osascript -e 'tell application "TextEdit" to quit saving no' >/dev/null 2>&1
set_whole_screen "$was_whole"
echo "fullscreen: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
