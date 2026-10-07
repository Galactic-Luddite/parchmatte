#!/usr/bin/env bash
# Runs the flicker scenarios against one window-cover mode and prints a
# summary: activation (Finder <-> TextEdit), same-app clicks, Cmd-`, and a
# second window moved across the covered one. Relaunches Parchmatte in the
# requested mode (which drops any covers the user had), and restores the
# preferences file afterwards.
# Usage: Tests/Harness/clip_compare.sh stacked|clipped [rounds] [app path]
set -uo pipefail
source "$(dirname "$0")/lib.sh"
MODE=${1:-stacked}
ROUNDS=${2:-20}
APP=${3:-$HARNESS/../../dist/Parchmatte.app}
PREFS_FILE="$PREFS.plist"
cp "$PREFS_FILE" $PM_TMP/pm/prefs-backup-$MODE 2>/dev/null
relaunch() {
    osascript -e 'quit app "Parchmatte"' >/dev/null 2>&1; sleep 1.2
    open "$APP"; sleep 2
}
if [ "$MODE" = clipped ]; then defaults write "$PREFS" clippedWindowCovers -bool YES
else defaults delete "$PREFS" clippedWindowCovers 2>/dev/null; fi
defaults write "$PREFS" maskTrace -bool YES
relaunch
log stream --style compact --predicate 'subsystem == "com.galacticluddite.parchmatte" AND category == "mask"' > $PM_TMP/pm/$MODE-mask.log 2>/dev/null &
LOGPID=$!
sleep 1
export OCC=1
"$HARNESS/activation_run.sh" "$ROUNDS" "$MODE-act" > /dev/null 2>&1
"$HARNESS/samewin_run.sh" click "$ROUNDS" "$MODE-click" > /dev/null 2>&1
"$HARNESS/samewin_run.sh" cycle "$ROUNDS" "$MODE-cycle" > /dev/null 2>&1
"$HARNESS/samewin_run.sh" occlude 40 "$MODE-occlude" > /dev/null 2>&1
kill "$LOGPID" 2>/dev/null
for t in act click cycle occlude; do
    echo "$MODE $t: $(tail -1 $PM_TMP/pm/$MODE-$t.txt)"
    if [ "$MODE" = clipped ]; then
        echo "$MODE $t clip: $(python3 "$HARNESS/mask_lag.py" $PM_TMP/pm/$MODE-$t.occ $PM_TMP/pm/$MODE-mask.log)"
    fi
done
defaults delete "$PREFS" maskTrace 2>/dev/null
defaults delete "$PREFS" clippedWindowCovers 2>/dev/null
