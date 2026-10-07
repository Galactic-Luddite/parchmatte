#!/usr/bin/env bash
# Window-cover motion diagnostics: desktop swipe out and back, a real mouse
# drag from rest, a drag that tiles the window at the screen's left edge,
# and a click that re-activates the covered app. Each phase writes a 120 Hz
# probe timeline to $OUT/<phase>.txt; summaries go to stdout.
# Usage: [PHASES="drag tile"] Tests/Harness/motion_run.sh [out dir]
set -uo pipefail
source "$(dirname "$0")/lib.sh"
OUT="${1:-$PM_TMP/pm-motion}"; mkdir -p "$OUT"
mkdir -p "$BIN"
for t in probe drag click covers check_cover activate_app; do
    [ -x "$BIN/$t" ] && [ "$BIN/$t" -nt "$HARNESS/$t.swift" ] || swiftc -O "$HARNESS/$t.swift" -o "$BIN/$t" || exit 2
done
was_whole=$(whole_screen && echo on || echo off)
set_whole_screen off
ensure_textedit
place() { textedit "set bounds of window 1 to {200, 150, 1000, 750}"; }
open_textedit_window "MOTION" 200 150 1000 750
cover_front || { echo "cover did not land"; exit 1; }

phase() {  # phase <name> <seconds> <command...>: probe while running a step
    local name=$1 secs=$2; shift 2
    bring_front TextEdit; place; sleep 2   # tracker back at its idle rate
    "$BIN/probe" TextEdit "$secs" --timeline ${PROBE_FLAGS:-} > "$OUT/$name.txt" &
    local p=$!
    sleep 0.4
    "$@"
    wait "$p"
    echo "$name: $(tail -1 "$OUT/$name.txt")"
}
swipe() {
    osascript -e 'tell application "System Events" to key code 124 using {control down}'
    sleep 2
    osascript -e 'tell application "System Events" to key code 123 using {control down}'
}
rapid() {  # three quick out-and-back swipes, reversing before macOS settles
    local i
    for i in 1 2 3; do
        osascript -e 'tell application "System Events" to key code 124 using {control down}'; sleep 0.45
        osascript -e 'tell application "System Events" to key code 123 using {control down}'; sleep 0.6
    done
}
reactivate() { open -a Finder; sleep 0.8; "$BIN/click" 600 450; }

# PHASES selects which to run (default all); drags are real mouse drags.
for ph in ${PHASES:-swipe rapid drag slow fastdrag tile click}; do
    case $ph in
        swipe) phase swipe 6 swipe ;;
        rapid) phase rapid 6 rapid ;;
        drag) phase drag 3 "$BIN/drag" 600 162 900 322 1.0 60 ;;
        slow) phase slow 4 "$BIN/drag" 600 162 900 322 2.5 150 ;;
        fastdrag) phase fastdrag 2 "$BIN/drag" 600 162 1100 422 0.4 24 ;;
        tile) phase tile 5 "$BIN/drag" 600 162 3 500 0.6 30
              "$BIN/check_cover" TextEdit; echo "after-tile check exit=$?" ;;
        click) phase click 3 reactivate ;;
    esac
done

place; bring_front TextEdit; hotkey 35; sleep 0.5   # remove only this cover
textedit_reset
osascript -e 'tell application "TextEdit" to quit saving no' >/dev/null 2>&1
set_whole_screen "$was_whole"
