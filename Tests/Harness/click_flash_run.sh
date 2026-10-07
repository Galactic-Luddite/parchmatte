#!/usr/bin/env bash
# Click flash: clicks inside a covered window of an app that is already in
# front, first at a normal size and then zoomed to the visible frame, and
# counts samples where the cover is stacked under the window (a flash) or
# missing. Safari with a blank page by default; TextEdit with APP=TextEdit.
# Usage: [APP=Safari] Tests/Harness/click_flash_run.sh [out dir]
set -uo pipefail
source "$(dirname "$0")/lib.sh"
APP=${APP:-Safari}
OUT="${1:-$PM_TMP/pm-clickflash}"; mkdir -p "$OUT" "$BIN"
for t in probe click covers check_cover activate_app; do
    [ -x "$BIN/$t" ] && [ "$BIN/$t" -nt "$HARNESS/$t.swift" ] || swiftc -O "$HARNESS/$t.swift" -o "$BIN/$t" || exit 2
done
was_whole=$(whole_screen && echo on || echo off)
set_whole_screen off
app() { osascript -e "tell application \"$APP\"" -e "$1" -e "end tell"; }
if [ "$APP" = Safari ]; then
    app 'make new document with properties {URL:"about:blank"}' >/dev/null
else
    ensure_textedit; app 'make new document with properties {text:"CLICK"}' >/dev/null
fi
sleep 1.5
app 'set bounds of window 1 to {200, 150, 1000, 750}' >/dev/null
bring_front "$APP" || exit 1
hotkey 35; wait_for_cover "$APP" || { echo "cover did not land"; exit 1; }
sleep 1.5
run() {  # run <name> <x> <y>: 12 clicks at (x,y) while probing
    "$BIN/probe" "$APP" 6 --timeline --vsync > "$OUT/$1.txt" &
    local p=$!
    sleep 0.5
    for i in $(seq 1 12); do "$BIN/click" "$2" "$3"; sleep 0.4; done
    wait "$p"
    echo "$1: $(tail -1 "$OUT/$1.txt")"
}
run normal 600 500
app 'set bounds of window 1 to {0, 39, 2056, 1329}' >/dev/null; sleep 1.5
"$BIN/covers" "$APP" | head -3
run zoomed 1000 800
app 'set bounds of window 1 to {200, 150, 1000, 750}' >/dev/null; sleep 1
bring_front "$APP"; hotkey 35; sleep 0.5
app 'close window 1' >/dev/null 2>&1
set_whole_screen "$was_whole"
