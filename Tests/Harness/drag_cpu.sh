#!/usr/bin/env bash
# CPU cost of tracking while a covered window is dragged: launches each
# app bundle in turn, drags the window continuously for 4 s with a real
# mouse drag, and samples the app's CPU with top once a second during the
# drag and again at rest. Prints peak and mean % per bundle, labelled by
# its grandparent directory.
# Usage: drag_cpu.sh <app bundle>...
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib.sh"
for t in drag covers check_cover activate_app; do
    [ -x "$BIN/$t" ] && [ "$BIN/$t" -nt "$HERE/$t.swift" ] || swiftc -O "$HERE/$t.swift" -o "$BIN/$t" || exit 2
done
restore=$(ps -o args= -p "$(pgrep -x Parchmatte | head -1)" 2>/dev/null | sed 's|/Contents/MacOS/Parchmatte.*||')
sample() {  # sample <pid> <seconds>: mean and peak %CPU over 1 s intervals
    # top prints one %CPU line per sample; the first sample is since launch.
    top -pid "$1" -l $(( $2 + 1 )) -s 1 -stats cpu 2>/dev/null | awk '/^[0-9.]+$/' | tail -n +2 \
        | awk '{s+=$1; if($1>m)m=$1; n++} END{printf "mean=%.1f%% peak=%.1f%%", n?s/n:0, m}'
}
for app in "$@"; do
    set=$(basename "$(dirname "$(dirname "$app")")")
    osascript -e 'tell application id "com.galacticluddite.parchmatte" to quit' >/dev/null 2>&1; sleep 1
    pkill -x Parchmatte 2>/dev/null; sleep 1
    open -n "$app"
    sleep 4
    pid=$(pgrep -x Parchmatte | head -1)
    set_whole_screen off
    ensure_textedit
    open_textedit_window "CPU" 200 150 1000 750
    cover_front >/dev/null || { echo "$set: cover did not land"; continue; }
    sleep 2
    "$BIN/drag" 600 162 1100 662 4.0 240 &
    d=$!
    drag=$(sample "$pid" 4)
    wait "$d"; sleep 2.5
    rest=$(sample "$pid" 3)
    echo "$set: dragging $drag; rest $rest"
    textedit "set bounds of window 1 to {200, 150, 1000, 750}" >/dev/null
    bring_front TextEdit >/dev/null; hotkey 35; sleep 0.5
    textedit_reset
done
osascript -e 'tell application "TextEdit" to quit saving no' >/dev/null 2>&1
pkill -x Parchmatte 2>/dev/null; sleep 1
[ -n "$restore" ] && open "$restore"
