#!/usr/bin/env bash
# Window-cover scenarios (test plan section C) using TextEdit as the target.
# Leaves Paper Whole Screen as it found it.
#
# Usage: Tests/Harness/scenarios_windows.sh
set -uo pipefail
source "$(dirname "$0")/lib.sh"

was_whole=$(whole_screen && echo on || echo off)
set_whole_screen off
ensure_textedit

# C0: basic cover on the built-in display.
open_textedit_window "A" 200 150 1000 750
cover_front
expect "C0 cover aligns on built-in" "$BIN/check_cover" TextEdit

# C1: move and resize, then settle.
textedit 'set bounds of window 1 to {300, 200, 1300, 900}'; sleep 0.4
expect "C1 follows move+resize" "$BIN/check_cover" TextEdit

# C2: minimize hides the cover; restore brings it back.
textedit 'set miniaturized of window 1 to true'; sleep 1.2
expect "C2 minimized -> no cover" "$BIN/check_cover" TextEdit --expect-uncovered --rect 300 200 1000 700
textedit 'set miniaturized of window 1 to false'; sleep 1.2
expect "C2 restored -> cover back" "$BIN/check_cover" TextEdit

# C2b: hold past the closed-window cleanup threshold. Keep this exact
# window reference; reopening the app can create an unrelated document.
textedit 'set miniaturized of window 1 to true'; sleep 4.5
expect "C2b long minimize -> no cover" "$BIN/check_cover" TextEdit --expect-uncovered --rect 300 200 1000 700
textedit 'set miniaturized of window 1 to false'; sleep 1.2
expect "C2b same window after long minimize -> cover back" "$BIN/check_cover" TextEdit

# C3: hide the app, then unhide.
osascript -e 'tell application "System Events" to set visible of process "TextEdit" to false'; sleep 1.2
expect "C3 hidden app -> no cover" "$BIN/check_cover" TextEdit --expect-uncovered --rect 300 200 1000 700
bring_front TextEdit; sleep 1
expect "C3 unhidden -> cover back" "$BIN/check_cover" TextEdit

# C9: an identical window of the same app stacked behind; minimizing the
# covered one must not move its cover onto the look-alike.
open_textedit_window "B" 300 200 1300 900
textedit 'set index of window 2 to 1'; sleep 0.6   # bring A (covered) back to front
textedit 'set miniaturized of window 1 to true'; sleep 1.5
expect "C9 look-alike not adopted" "$BIN/check_cover" TextEdit --expect-uncovered --rect 300 200 1000 700
textedit 'set miniaturized of every window to false'; sleep 1.2

# C4: closing the covered window removes the cover.
textedit_reset; sleep 4
expect "C4 closed -> cover removed" "$BIN/check_cover" TextEdit --expect-uncovered --rect 300 200 1000 700

# C4b: closing several covered windows immediately before global visibility
# changes must not strand their individual paper windows. This reproduces the
# sequence that previously left all five performance-test covers on screen:
# target teardown, whole-screen on/off, then Snooze on/off before the normal
# closed-window grace period had elapsed.
for i in 1 2 3 4 5; do
    left=$((45 + i * 60)); top=$((63 + i * 40))
    open_textedit_window "Close $i" "$left" "$top" $((left + 590)) $((top + 394))
    cover_front
    expect "C4b target $i initially covered" "$BIN/check_cover" TextEdit --rect "$left" "$top" 590 394
done
textedit_reset
# Drive the visibility changes inside the cleanup grace period. The settled
# `set_whole_screen` helper deliberately waits and would let the ordinary
# missing-window scan remove these covers before exercising this race.
hotkey 31; sleep 0.05
hotkey 31; sleep 0.05
hotkey 1; sleep 0.05
hotkey 1; sleep 1
for i in 1 2 3 4 5; do
    left=$((45 + i * 60)); top=$((63 + i * 40))
    expect "C4b closed cover $i absent after whole-screen and Snooze" \
        bash -c 'actual=$("$1" Parchmatte) || exit $?; ! grep -Eq "^Parchmatte [0-9]+ $2,$3 590x394$" <<< "$actual"' \
        _ "$BIN/covers" "$left" "$top"
done

# C2d: the failed narrow-window restore with another same-app window behind
# it. Retain an AppleScript reference through each long minimize, and check
# each restore against the target's explicit footprint, not whichever sibling
# happens to be frontmost. A small opening stretch must not poison that size.
open_textedit_window "Restore neighbour" 234 103 1017 686
open_textedit_window "Restore target" 900 150 1500 650
cover_front
expect "C2d narrow target initially covered" "$BIN/check_cover" TextEdit --rect 900 150 600 500
expect "C2d three same-window long holds with neighbour restore covered" osascript - "$BIN/check_cover" <<'APPLESCRIPT'
on run argv
    set checker to item 1 of argv
    tell application "TextEdit"
        set targetID to id of window 1
        repeat 3 times
            set miniaturized of window id targetID to true
            delay 4.5
            do shell script quoted form of checker & " TextEdit --expect-uncovered --rect 900 150 600 500"
            set miniaturized of window id targetID to false
            delay 1.2
            do shell script quoted form of checker & " TextEdit --rect 900 150 600 500"
            do shell script quoted form of checker & " TextEdit --expect-uncovered --rect 234 103 783 583"
        end repeat
    end tell
    return "all three restores aligned; neighbour remains uncovered"
end run
APPLESCRIPT
textedit_reset; sleep 4

# C5: quitting the app removes covers.
open_textedit_window "Q" 200 150 1000 750
cover_front
osascript -e 'tell application "TextEdit" to quit saving no'; sleep 4
expect "C5 quit -> cover removed" "$BIN/check_cover" TextEdit --expect-uncovered --rect 200 150 800 600

# A2: cover a window on the second (1x) display, if one is connected.
# `screens` prints AppKit frames ("frame=X,Y WxH"); AppleScript bounds use a
# top-left origin measured from the main display's top edge.
if [ "$("$BIN/screens" | wc -l)" -ge 2 ]; then
    ensure_textedit
    geo() { "$BIN/screens" | sed -n "${1}p" | sed -E 's/.*frame=(-?[0-9]+),(-?[0-9]+) ([0-9]+)x([0-9]+).*/\1 \2 \3 \4/'; }
    read -r sx sy sw sh <<< "$(geo 2)"
    read -r _ _ _ main_h <<< "$(geo 1)"
    top=$((main_h - sy - sh + 150)); left=$((sx + 150))
    open_textedit_window "U" "$left" "$top" $((left + 900)) $((top + 600))
    cover_front
    expect "A2 cover aligns on second display" "$BIN/check_cover" TextEdit
    textedit 'set miniaturized of window 1 to true'; sleep 4.5
    expect "A2 long minimize on second display -> no cover" "$BIN/check_cover" TextEdit --expect-uncovered --rect "$left" "$top" 900 600
    textedit 'set miniaturized of window 1 to false'; sleep 1.2
    expect "A2 same window restored on second display -> cover back" "$BIN/check_cover" TextEdit
    textedit_reset
fi

osascript -e 'tell application "TextEdit" to quit saving no' >/dev/null 2>&1
set_whole_screen "$was_whole"
echo "windows: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
