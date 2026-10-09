#!/usr/bin/env bash
# App Exposé (ctrl-down) and Mission Control (ctrl-up) over a covered TextEdit
# window: the cover must hide while the overview shows, never be re-created
# or shown away from its window, and be back over it afterwards.
# Leaves Paper Whole Screen as it found it; touches only the cover it adds.
#
# Usage: Tests/Harness/scenarios_expose.sh
set -uo pipefail
source "$(dirname "$0")/lib.sh"
was_whole=$(whole_screen && echo on || echo off)

expect "E1 App Expose hides cover, no chase/re-create" \
    bash -c "'$HARNESS/expo_probe_run.sh' expose >/dev/null 2>&1 && '$HARNESS/expo_check.sh' $PM_TMP/expo/expose.log"
expect "E1 cover back after App Expose" "$BIN/check_cover" TextEdit
uncover_front TextEdit || true
textedit_reset
osascript -e 'tell application "TextEdit" to quit saving no' >/dev/null 2>&1
sleep 1
expect "E2 Mission Control hides cover, no chase/re-create" \
    bash -c "'$HARNESS/expo_probe_run.sh' mc >/dev/null 2>&1 && '$HARNESS/expo_check.sh' $PM_TMP/expo/mc.log"
expect "E2 cover back after Mission Control" "$BIN/check_cover" TextEdit

uncover_front TextEdit || true
osascript -e 'tell application "TextEdit" to quit saving no' >/dev/null 2>&1
sleep 1
# Whole-screen paper must hide for the overview too (issue #7): the window
# server otherwise shrinks it into a tile above Mission Control.
main_home="$("$BIN/screens" 2>/dev/null | head -1 | grep -o '0,0 [0-9]*x[0-9]*' || echo '0,0 1920x1080')"
expect "E3 App Expose hides whole-screen paper" \
    bash -c "'$HARNESS/expo_probe_run.sh' expose whole >/dev/null 2>&1 && '$HARNESS/expo_check.sh' --whole $PM_TMP/expo/expose.log '$main_home'"
osascript -e 'tell application "TextEdit" to quit saving no' >/dev/null 2>&1
sleep 1
expect "E4 Mission Control hides whole-screen paper" \
    bash -c "'$HARNESS/expo_probe_run.sh' mc whole >/dev/null 2>&1 && '$HARNESS/expo_check.sh' --whole $PM_TMP/expo/mc.log '$main_home'"
osascript -e 'tell application "TextEdit" to quit saving no' >/dev/null 2>&1
set_whole_screen "$was_whole"
echo "expose: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
