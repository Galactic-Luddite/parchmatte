#!/usr/bin/env bash
# Network watch (security plan S4): samples Parchmatte's open network sockets
# every 2 s while exercising the app through its hotkeys, and fails if any
# socket ever appears.
#
# Usage: Tests/Harness/netwatch.sh [seconds]
set -uo pipefail

SECONDS_TOTAL="${1:-30}"
PID="$(pgrep -x Parchmatte)" || { echo "Parchmatte is not running"; exit 2; }

hotkey() { osascript -e "tell application \"System Events\" to key code $1 using {control down, option down}"; }
APP_PATH="$(ps -o comm= -p "$PID" | sed -E 's|/Contents/MacOS/.*||')"
APP_EXE="$APP_PATH/Contents/MacOS/Parchmatte"
pref() {
    "$APP_EXE" --audit-export-preferences | python3 -c \
        'import plistlib, sys; print(plistlib.loads(sys.stdin.buffer.read()).get(sys.argv[1], ""))' "$1"
}
start_lamp="$(pref lamp)" || exit 2
start_texture="$(pref texture)" || exit 2
start_whole="$(pref wholeScreen)" || exit 2
# Cycle a setting back with its hotkey until it matches where we started.
restore() {  # restore <key> <value> <keycode>
    local n
    for n in 1 2 3 4 5 6 7 8; do
        [ "$(pref "$1")" = "$2" ] && return 0
        hotkey "$3"; sleep 0.4
    done
    echo "FAIL could not restore $1 to its starting value" >&2
    return 1
}

seen=0
for ((i = 0; i < SECONDS_TOTAL / 2; i++)); do
    sockets="$(lsof -a -i -p "$PID" 2>/dev/null | tail -n +2)"
    if [ -n "$sockets" ]; then
        echo "$sockets"
        seen=$((seen + $(echo "$sockets" | wc -l)))
    fi
    case $((i % 4)) in
        0) hotkey 37 ;;  # cycle lamp
        1) hotkey 17 ;;  # cycle texture
        2) hotkey 31 ;;  # toggle whole screen
        3) hotkey 31 ;;  # and back
    esac
    sleep 2
done

restoration_failures=0
restore lamp "$start_lamp" 37 || restoration_failures=$((restoration_failures + 1))
restore texture "$start_texture" 17 || restoration_failures=$((restoration_failures + 1))
restore wholeScreen "$start_whole" 31 || restoration_failures=$((restoration_failures + 1))
echo "pid=$PID samples=$((SECONDS_TOTAL / 2)) sockets_seen=$seen"
[ "$seen" -eq 0 ] && [ "$restoration_failures" -eq 0 ]
