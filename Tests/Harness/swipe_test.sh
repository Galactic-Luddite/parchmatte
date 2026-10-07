#!/usr/bin/env bash
# Swipe test: samples whole-screen covers while switching one desktop right and
# back, and reports how many samples had the main display's cover off its
# screen (x != 0). Needs the app running with Paper Whole Screen on.
#
# Usage: Tests/Harness/swipe_test.sh
set -uo pipefail
cd "$(dirname "$0")"
out="$(mktemp)"
bin/screencovers 7 > "$out" &
probe=$!
sleep 1.5
osascript -e 'tell application "System Events" to key code 124 using {control down}'
sleep 2.5
osascript -e 'tell application "System Events" to key code 123 using {control down}'
wait "$probe"
sleep 1.5
# Lines look like: " 1.677 2 [\"-800,-1440 3440x1440\", \"3333,0 1728x1117\"]"
changes=$(grep -c '"' "$out")
offscreen=$(grep -vc '"0,0 ' "$out")
final="$(bin/screencovers 0.2 | head -1)"
echo "state_changes=$changes offscreen_states=$((offscreen - 1)) final=${final#* }"
rm -f "$out"
