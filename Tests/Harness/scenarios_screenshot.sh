#!/usr/bin/env bash
# Portion screenshot picker (⌘⇧4) over a covered TextEdit window (issue #11):
# with Hide from Screenshots off the cover stays while the picker is up, so
# the capture includes the paper; with it on the cover steps aside and comes
# back after Escape. Relaunches the app to apply the setting; restores it
# and Paper Whole Screen as found.
#
# Usage: Tests/Harness/scenarios_screenshot.sh
set -uo pipefail
source "$(dirname "$0")/lib.sh"
DOMAIN=com.galacticluddite.parchmatte
APP="$(ps -o comm= -p "$(pgrep -x Parchmatte | head -1)" 2>/dev/null | sed 's|/Contents/MacOS/Parchmatte$||')"
[ -d "$APP" ] || { echo "Parchmatte app bundle not found (is the app running?)"; exit 2; }
was_hide=$(defaults read "$DOMAIN" hideFromScreenshots 2>/dev/null || echo 1)
was_whole=$(whole_screen && echo on || echo off)

relaunch_with() {  # relaunch_with on|off: Hide from Screenshots
    pkill -x Parchmatte; sleep 1
    if [ "$1" = on ]; then defaults write "$DOMAIN" hideFromScreenshots -bool true
    else defaults write "$DOMAIN" hideFromScreenshots -bool false; fi
    open "$APP"; sleep 2.5
}
picker() {   # open the portion picker; its UI window is the signal the app watches
    osascript -e 'tell application "System Events" to key code 21 using {command down, shift down}'
    sleep 0.8
}
dismiss() { osascript -e 'tell application "System Events" to key code 53'; sleep 0.8; }

relaunch_with off
set_whole_screen off
ensure_textedit
open_textedit_window "Shot" 200 150 1000 750
cover_front || echo "WARN cover did not appear"
picker
expect "P1 cover stays for the picker with Hide from Screenshots off" "$BIN/check_cover" TextEdit
dismiss
expect "P1 cover still there after Escape" "$BIN/check_cover" TextEdit
uncover_front TextEdit || true
textedit_reset

relaunch_with on
ensure_textedit
open_textedit_window "Shot" 200 150 1000 750
cover_front || echo "WARN cover did not appear"
picker
expect "P2 cover steps aside for the picker with Hide from Screenshots on" "$BIN/check_cover" TextEdit --expect-uncovered
dismiss
expect "P2 cover back after Escape" wait_for_cover TextEdit
uncover_front TextEdit || true
textedit_reset
osascript -e 'tell application "TextEdit" to quit saving no' >/dev/null 2>&1

if [ "$was_hide" = 1 ]; then relaunch_with on; else relaunch_with off; fi
set_whole_screen "$was_whole"
echo "screenshot: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
