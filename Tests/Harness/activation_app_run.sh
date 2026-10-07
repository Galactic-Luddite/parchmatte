#!/usr/bin/env bash
# activation_run.sh for an app that is already open (Ghostty, say): covers its
# front window, switches to Finder and back N times with `open -a` while
# actprobe watches, then removes only that cover.
# Usage: Tests/Harness/activation_app_run.sh <app> [rounds] [tag]
set -uo pipefail
source "$(dirname "$0")/lib.sh"
APP=$1
ROUNDS=${2:-20}
TAG=${3:-act-app}
mkdir -p $PM_TMP/pm
[ -x "$BIN/actprobe" ] && [ "$BIN/actprobe" -nt "$HARNESS/actprobe.swift" ] || swiftc -O "$HARNESS/actprobe.swift" -o "$BIN/actprobe"
was_whole=$(whole_screen && echo on || echo off)
set_whole_screen off
bring_front "$APP"; hotkey 35; sleep 0.8
"$BIN/check_cover" "$APP"
SECS=$(echo "$ROUNDS * 1.6 + 1" | bc)
"$BIN/actprobe" "$APP" "$SECS" --timeline > "$PM_TMP/pm/$TAG.txt" &
sleep 0.5
for r in $(seq 1 "$ROUNDS"); do
    open -a Finder; sleep 0.7
    open -a "$APP"; sleep 0.7
done
wait
cat "$PM_TMP/pm/$TAG.txt"
bring_front "$APP"; hotkey 35; sleep 0.5   # remove only this test's cover
set_whole_screen "$was_whole"
