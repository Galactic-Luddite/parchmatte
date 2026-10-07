#!/usr/bin/env bash
# Proves that the running build has registered its hotkeys and can create and
# remove a window cover before the first measured suite begins.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

ATTEMPTS="${PARCHMATTE_READY_ATTEMPTS:-10}"
was_whole=$(whole_screen && echo on || echo off)

cleanup() {
    uncover_front TextEdit >/dev/null 2>&1 || true
    textedit_reset
    osascript -e 'tell application "TextEdit" to quit saving no' >/dev/null 2>&1 || true
    set_whole_screen "$was_whole" >/dev/null 2>&1 || true
}
trap cleanup EXIT

set_whole_screen off || true
ensure_textedit
open_textedit_window "Harness readiness" 200 150 1000 750 || {
    echo "FAIL  readiness window did not appear"
    exit 1
}

for attempt in $(seq 1 "$ATTEMPTS"); do
    uncover_front TextEdit || true
    if ! bring_front TextEdit; then
        echo "WAIT  activation attempt $attempt/$ATTEMPTS failed"
        sleep 0.5
        continue
    fi
    hotkey 35
    sleep 0.8
    cover_result=$("$BIN/check_cover" TextEdit 2>&1)
    cover_rc=$?
    if [ "$cover_rc" -eq 0 ]; then
        echo "  ok    Parchmatte accepted the window-cover hotkey (attempt $attempt)"
        if uncover_front TextEdit; then
            echo "  ok    Parchmatte removed the readiness cover"
            exit 0
        fi
        echo "FAIL  Parchmatte did not remove the readiness cover"
        exit 1
    fi
    echo "WAIT  cover handshake attempt $attempt/$ATTEMPTS did not land: $cover_result (front=$(frontmost))"
done

echo "FAIL  Parchmatte did not become ready after $ATTEMPTS bounded attempts"
exit 1
