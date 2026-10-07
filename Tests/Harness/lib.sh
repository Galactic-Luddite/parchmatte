#!/usr/bin/env bash
# Shared helpers for window-cover scenario scripts. Source this file.
HARNESS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HARNESS/bin"
PM_TMP="${TMPDIR:-/tmp}"; PM_TMP="${PM_TMP%/}"   # scratch root for probe output
ACTIVATE_APP="${PARCHMATTE_ACTIVATE_APP:-$BIN/activate_app}"
PREFS="$HOME/Library/Containers/com.galacticluddite.parchmatte/Data/Library/Preferences/com.galacticluddite.parchmatte"

hotkey() { osascript -e "tell application \"System Events\" to key code $1 using {control down, option down}"; }
whole_screen() {
    # A sandboxed release app keeps UserDefaults in its container, which an
    # external `defaults read` may silently fail to see on current macOS.
    # Read the app's checked menu state rather than treating that failure as
    # off. An on-screen-cover probe would also be wrong while an app is
    # excluded or the cover is temporarily suppressed.
    local mark
    mark=$(osascript -e 'tell application "System Events" to tell process "Parchmatte" to get value of attribute "AXMenuItemMarkChar" of menu item "Paper Whole Screen" of menu 1 of menu bar item 1 of menu bar 1') || return 2
    [ "$mark" = "✓" ]
}
is_whole() { if [ "$1" = on ]; then whole_screen; else ! whole_screen; fi; }
set_whole_screen() {  # set_whole_screen on|off; toggles once, then waits for it to land
    local want=$1 i
    is_whole "$want" && return 0
    hotkey 31
    # The app writes the preference asynchronously; poll instead of retrying,
    # or a second press flips it straight back.
    for i in $(seq 1 30); do
        is_whole "$want" && { sleep 0.3; return 0; }
        sleep 0.1
    done
    echo "WARN whole screen did not become $want" >&2
    return 1
}
frontmost() {
    osascript <<'APPLESCRIPT'
tell application "System Events"
    repeat with candidate in application processes
        if frontmost of candidate then return name of candidate
    end repeat
    return ""
end tell
APPLESCRIPT
}
is_front() {  # is_front <app>
    osascript - "$1" <<'APPLESCRIPT'
on run argv
    tell application "System Events" to get frontmost of process (item 1 of argv)
end run
APPLESCRIPT
}
# `open -a` reliably launches an application, but macOS can decline the
# activation when Terminal is in the background. Use the public AppKit helper
# to request foreground activation explicitly, then confirm before continuing.
bring_front() {  # bring_front <app>
    local i
    for i in 1 2 3 4 5; do
        open -a "$1"
        "$ACTIVATE_APP" "$1" >/dev/null 2>&1 || true
        sleep 0.2
        [ "$(is_front "$1")" = true ] && return 0
    done
    echo "WARN could not bring $1 to the front (front is $(frontmost))" >&2
    return 1
}
wait_for_cover() {  # wait_for_cover <app>
    local i
    for i in $(seq 1 30); do
        "$BIN/check_cover" "$1" >/dev/null 2>&1 && return 0
        sleep 0.1
    done
    "$BIN/check_cover" "$1" >&2
    return 1
}
wait_for_uncovered() {  # wait_for_uncovered <app>
    local i
    for i in $(seq 1 30); do
        "$BIN/check_cover" "$1" --expect-uncovered >/dev/null 2>&1 && return 0
        sleep 0.1
    done
    "$BIN/check_cover" "$1" --expect-uncovered >&2
    return 1
}
cover_front() {  # Add a cover to the front TextEdit window and prove it landed.
    bring_front TextEdit || return 1
    hotkey 35 || return 1
    wait_for_cover TextEdit
}
uncover_front() {  # Remove only the front window's cover; preserve every other cover.
    local app=${1:-TextEdit}
    bring_front "$app" || return 1
    if "$BIN/check_cover" "$app" >/dev/null 2>&1; then
        hotkey 35 || return 1
    fi
    wait_for_uncovered "$app"
}
ensure_textedit() {
    open -a TextEdit; sleep 1.5
    # A cold launch can show the Open panel instead of a document; dismiss it.
    osascript -e 'tell application "System Events" to tell process "TextEdit"
        if exists (first window whose subrole is "AXDialog" or name is "Open") then key code 53
    end tell' >/dev/null 2>&1
    osascript -e 'tell application "TextEdit" to close every document saving no' >/dev/null 2>&1
    sleep 0.5
}
textedit() { osascript -e "tell application \"TextEdit\"" -e "$1" -e "end tell"; }
textedit_reset() {
    osascript -e 'tell application "TextEdit" to close every document saving no' >/dev/null 2>&1
}
open_textedit_window() {  # open_textedit_window <label> <left> <top> <right> <bottom>
    local i
    # Create the document once (a retry would leave a second window behind),
    # then wait for it to be on screen where asked.
    textedit "activate
set d to make new document with properties {text:\"$1\"}
delay 0.4
set bounds of window 1 to {$2, $3, $4, $5}" >/dev/null 2>&1
    for i in $(seq 1 30); do
        "$BIN/covers" TextEdit | grep -q "^TextEdit .* $2,$3 " && { sleep 0.3; return 0; }
        sleep 0.1
        [ "$i" = 15 ] && textedit "set bounds of window 1 to {$2, $3, $4, $5}" >/dev/null 2>&1
    done
    echo "WARN TextEdit window $1 did not appear" >&2
    return 1
}

PASS=0 FAIL=0
expect() {  # expect <name> <command...>: record pass/fail for a check
    local name="$1"; shift
    local out; out="$("$@" 2>&1)"; local code=$?
    if [ $code -eq 0 ]; then PASS=$((PASS + 1)); echo "PASS  $name  $out"
    else FAIL=$((FAIL + 1)); echo "FAIL  $name  $out"; fi
}
