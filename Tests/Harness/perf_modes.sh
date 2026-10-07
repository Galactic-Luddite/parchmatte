#!/usr/bin/env bash
# CPU of window covers at rest, in one mode (stacked|clipped): a covered
# TextEdit window with a second TextEdit window beside it, measured with
# TextEdit in front (the 120 Hz same-app watch) and with Finder in front
# (idle rate). Relaunches Parchmatte in that mode (drops the user's covers).
# Usage: Tests/Harness/perf_modes.sh stacked|clipped [seconds] [app path]
set -uo pipefail
source "$(dirname "$0")/lib.sh"
MODE=${1:-stacked}
SECS=${2:-20}
APP=${3:-$HARNESS/../../dist/Parchmatte.app}
if [ "$MODE" = clipped ]; then defaults write "$PREFS" clippedWindowCovers -bool YES
else defaults delete "$PREFS" clippedWindowCovers 2>/dev/null; fi
osascript -e 'quit app "Parchmatte"' >/dev/null 2>&1; sleep 1.2
open "$APP"; sleep 2
was_whole=$(whole_screen && echo on || echo off)
set_whole_screen off
"$HARNESS/perf.sh" "$SECS" "$MODE no-covers"
ensure_textedit
open_textedit_window "A" 200 150 1000 750
cover_front
open_textedit_window "B" 700 500 1300 900
sleep 2; "$BIN/check_cover" TextEdit; pgrep -x Parchmatte
"$HARNESS/perf.sh" "$SECS" "$MODE textedit-front-2win"
open -a Finder; sleep 2
"$HARNESS/perf.sh" "$SECS" "$MODE finder-front"
bring_front TextEdit
"$BIN/click" 300 250; sleep 0.4
hotkey 35; sleep 0.5
textedit_reset
osascript -e 'tell application "TextEdit" to quit saving no' >/dev/null 2>&1
set_whole_screen "$was_whole"
defaults delete "$PREFS" clippedWindowCovers 2>/dev/null
