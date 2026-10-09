#!/usr/bin/env bash
# Probes App Exposé (ctrl-down) and Mission Control (ctrl-up) with a covered
# TextEdit window. Writes timelines + screenshots to $PM_TMP/expo.
# Usage: expo_probe_run.sh [expose|mc] [whole]
set -uo pipefail
source "$(dirname "$0")/lib.sh"
MODE="${1:-expose}"
OUT=$PM_TMP/expo; mkdir -p "$OUT"
rm -f "$OUT/$MODE.log"
swiftc -O -o "$BIN/expoprobe" "$HARNESS/expoprobe.swift" || exit 2
WHOLE="${2:-}"
ensure_textedit
open_textedit_window "Expose" 200 150 1000 750
if [ "$WHOLE" = whole ]; then
    set_whole_screen on
    bring_front TextEdit || exit 1
else
    set_whole_screen off
    cover_front || { echo "TextEdit cover did not appear"; exit 1; }
fi
if [ "$WHOLE" = whole ]; then
    "$BIN/screencovers" 0.2 | head -1 | grep -q '"0,0 ' || { echo "main screen not covered"; exit 1; }
else
    "$BIN/check_cover" TextEdit || exit 1
fi
[ "$(frontmost)" = TextEdit ] || { echo "TextEdit not front"; exit 1; }
KEY=125; [ "$MODE" = mc ] && KEY=126
"$BIN/expoprobe" TextEdit 4 > "$OUT/$MODE.log" &
P=$!
sleep 0.3
osascript -e "tell application \"System Events\" to key code $KEY using control down"
sleep 0.25; screencapture -x "$OUT/$MODE-a.png"
sleep 0.9; screencapture -x "$OUT/$MODE-b.png"
osascript -e 'tell application "System Events" to key code 53'
sleep 0.2; screencapture -x "$OUT/$MODE-c.png"
wait $P
sleep 0.5; screencapture -x "$OUT/$MODE-d.png"
if [ "$WHOLE" = whole ]; then
    "$BIN/screencovers" 0.2 | head -1 | grep -q '"0,0 ' || { echo "main screen not covered after"; exit 1; }
    set_whole_screen off
else
    "$BIN/check_cover" TextEdit
fi
echo done
