#!/usr/bin/env bash
# Carry (TEST_PLAN B7): holds a covered TextEdit window by its title bar and
# switches one desktop to the right, so the window lands on the next desktop
# without its cover, and reports how long it sat bare. The cover cannot ride
# along (it belongs to the desktop being left), so some bare time during the
# slide is expected; compare builds rather than expecting zero.
# Needs two desktops with the current one on the left.
# Usage: Tests/Harness/carry_run.sh [out dir]
set -uo pipefail
source "$(dirname "$0")/lib.sh"
OUT="${1:-$PM_TMP/pm-carry}"; mkdir -p "$OUT" "$BIN"
for t in probe carry covers check_cover activate_app; do
    [ -x "$BIN/$t" ] && [ "$BIN/$t" -nt "$HARNESS/$t.swift" ] || swiftc -O "$HARNESS/$t.swift" -o "$BIN/$t" || exit 2
done
was_whole=$(whole_screen && echo on || echo off)
set_whole_screen off
ensure_textedit; textedit_reset
osascript -e 'tell application "TextEdit" to make new document with properties {text:"CARRY"}' >/dev/null
sleep 1
osascript -e 'tell application "TextEdit" to set bounds of window 1 to {200, 150, 1000, 750}' >/dev/null
bring_front TextEdit || exit 1
hotkey 35; wait_for_cover TextEdit || { echo "cover did not land"; exit 1; }
sleep 1
"$BIN/probe" TextEdit 6 --timeline --vsync > "$OUT/carry.txt" &
probe=$!
sleep 0.7
"$BIN/carry" 600 162 &
carry=$!
sleep 1.3
osascript -e 'tell application "System Events" to key code 124 using {control down}'
wait "$carry"; wait "$probe"
tail -1 "$OUT/carry.txt"
if grep -q 'covers=\["-' "$OUT/carry.txt"; then echo "desktop switched: yes"; else echo "desktop switched: NO (result is not a carry)"; fi
"$BIN/check_cover" TextEdit
osascript -e 'tell application "TextEdit" to close window 1 saving no' >/dev/null 2>&1
osascript -e 'tell application "System Events" to key code 123 using {control down}'
sleep 1.5
set_whole_screen "$was_whole"
