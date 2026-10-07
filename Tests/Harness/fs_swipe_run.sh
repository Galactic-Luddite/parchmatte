#!/usr/bin/env bash
# Swipes between a full-screen Space and the desktop holding a covered
# window, slowly and then quickly, while the probe records the covered
# 800x600 window. Shows how long the window sits bare after each return.
# Usage: Tests/Harness/fs_swipe_run.sh [out dir]
set -uo pipefail
source "$(dirname "$0")/lib.sh"
OUT="${1:-$PM_TMP/pm-fsswipe}"; mkdir -p "$OUT" "$BIN"
for t in probe covers check_cover activate_app; do
    [ -x "$BIN/$t" ] && [ "$BIN/$t" -nt "$HARNESS/$t.swift" ] || swiftc -O "$HARNESS/$t.swift" -o "$BIN/$t" || exit 2
done
was_whole=$(whole_screen && echo on || echo off)
set_whole_screen off
ensure_textedit
open_textedit_window "COVERED" 200 150 1000 750
cover_front || { echo "cover did not land"; exit 1; }
# A second document goes full screen; macOS puts its Space right of this one.
textedit 'make new document with properties {text:"FULL"}' >/dev/null; sleep 0.6
osascript -e 'tell application "System Events" to tell process "TextEdit" to set value of attribute "AXFullScreen" of window 1 to true'
sleep 2.5
key() { osascript -e "tell application \"System Events\" to key code $1 using {control down}"; }
"$BIN/probe" TextEdit 14 --timeline > "$OUT/fsswipe.txt" &
p=$!
sleep 0.5
for d in 1.5 1.5 0.5 0.5 0.5; do key 123; sleep "$d"; key 124; sleep "$d"; done
key 123
wait "$p"
SIZE=800x600 python3 "$HARNESS/motion_lag.py" "$OUT/fsswipe.txt"
# Leave full screen and clean up.
osascript -e 'tell application "System Events" to tell process "TextEdit" to set value of attribute "AXFullScreen" of (first window whose value of attribute "AXFullScreen" is true) to false' >/dev/null 2>&1
sleep 2
bring_front TextEdit; hotkey 35; sleep 0.5
textedit_reset
osascript -e 'tell application "TextEdit" to quit saving no' >/dev/null 2>&1
set_whole_screen "$was_whole"
