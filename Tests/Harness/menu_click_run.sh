#!/usr/bin/env bash
# Menu by mouse: opens the status menu with a real click and chooses
# "Paper TextEdit Window" with a real click, then removes it the same way.
# Opening the menu with the mouse makes this app frontmost on current macOS,
# which the hotkey and accessibility-press paths the other suites use never
# exercise; the item must still act on the app in use.
# Usage: Tests/Harness/menu_click_run.sh
set -uo pipefail
source "$(dirname "$0")/lib.sh"
for t in click covers check_cover activate_app; do
    [ -x "$BIN/$t" ] && [ "$BIN/$t" -nt "$HARNESS/$t.swift" ] || swiftc -O "$HARNESS/$t.swift" -o "$BIN/$t" || exit 2
done
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then echo "PASS  $1"; pass=$((pass + 1)); else echo "FAIL  $1 (got $2, want $3)"; fail=$((fail + 1)); fi; }
ax() { osascript -e 'tell application "System Events" to tell process "Parchmatte"' -e "$1" -e 'end tell' 2>/dev/null | tr -d ' '; }
click_item() {  # click_item <name prefix>: open the menu and click the item, both with the mouse
    local p x y
    p=$(ax 'get position of menu bar item 1 of menu bar 1'); [ -n "$p" ] || return 1
    "$BIN/click" $(( ${p%,*} + 12 )) $(( ${p#*,} + 12 )); sleep 1
    p=$(ax "get position of (first menu item of menu 1 of menu bar item 1 of menu bar 1 whose name starts with \"$1\")")
    if [ -z "$p" ]; then osascript -e 'tell application "System Events" to key code 53'; return 1; fi
    x=$(( ${p%,*} + 100 )); y=$(( ${p#*,} + 12 ))
    "$BIN/click" "$x" "$y"; sleep 1.2
}
count() { "$BIN/covers" | sed -n 's/^windowCovers=//p'; }

was_whole=$(whole_screen && echo on || echo off)
set_whole_screen off
ensure_textedit; textedit_reset
osascript -e 'tell application "TextEdit" to make new document with properties {text:"MENU"}' >/dev/null
sleep 1
osascript -e 'tell application "TextEdit" to set bounds of window 1 to {200, 150, 1000, 750}' >/dev/null
bring_front TextEdit || exit 1
sleep 0.5

click_item "Paper TextEdit Window"; check "M1 mouse menu covers the front window" "$(count)" 1
check "M1 cover sits on the window" "$("$BIN/check_cover" TextEdit >/dev/null 2>&1 && echo yes || echo no)" yes
check "M2 menu names the app in use after a mouse open" "$(osascript -e 'tell application "System Events" to tell process "Parchmatte" to get name of menu item 4 of menu 1 of menu bar item 1 of menu bar 1' 2>/dev/null)" "Remove Paper from TextEdit Window"
click_item "Remove Paper from TextEdit Window"; check "M3 mouse menu removes the cover" "$(count)" 0

osascript -e 'tell application "TextEdit" to close window 1 saving no' >/dev/null 2>&1
set_whole_screen "$was_whole"
echo "menu_click: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
