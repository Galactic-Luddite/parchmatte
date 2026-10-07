#!/usr/bin/env bash
# Fast, bounded checks for the Terminal permissions the GUI harness needs.
# Run from Terminal so the Apple Events use the same TCC identity as the audit.
set -uo pipefail

OSASCRIPT="${PARCHMATTE_OSASCRIPT:-/usr/bin/osascript}"
OPEN="${PARCHMATTE_OPEN:-/usr/bin/open}"
SLEEP="${PARCHMATTE_SLEEP:-/bin/sleep}"
ACTIVATE_APP="${PARCHMATTE_ACTIVATE_APP:-$(cd "$(dirname "$0")" && pwd)/bin/activate_app}"
FAIL=0

check() {  # check <label> <osascript arguments...>
    local label=$1 output rc
    shift
    output="$("$OSASCRIPT" "$@" 2>&1)"; rc=$?
    if [ "$rc" -eq 0 ]; then
        echo "  ok    $label"
    else
        echo "  FAIL  $label: $output"
        FAIL=1
    fi
}

# macOS 15 can defer Apple Events sent by a background Terminal even when its
# TCC grants are present. Activate Terminal through AppKit before asking it to
# drive System Events; this replaces the otherwise-required click on the
# remotely opened Terminal window.
terminal_assisted=false
for _ in 1 2 3; do
    if "$ACTIVATE_APP" --click Terminal >/dev/null 2>&1; then
        terminal_assisted=true
        break
    fi
    "$SLEEP" 0.2
done
if [ "$terminal_assisted" = true ]; then
    echo "  ok    Terminal foreground assist landed"
else
    # The assist is only a way to wake up already-granted Automation. The
    # functional System Events check below is the authoritative requirement.
    echo "  note  Terminal foreground assist did not land; checking Automation directly"
fi

check "Terminal can drive System Events" \
    -e 'with timeout of 10 seconds' \
    -e 'tell application "System Events"' \
    -e 'if not UI elements enabled then error "Accessibility is not enabled for Terminal"' \
    -e 'get count of processes' \
    -e 'end tell' \
    -e 'end timeout'

check "Terminal can automate TextEdit" \
    -e 'with timeout of 10 seconds' \
    -e 'tell application "TextEdit"' \
    -e 'if (count windows) is 0 then make new document with properties {text:""}' \
    -e 'count windows' \
    -e 'end tell' \
    -e 'end timeout'

textedit_frontmost="false"
textedit_activation="not attempted"
for _ in 1 2 3 4 5; do
    "$OPEN" -a TextEdit
    "$SLEEP" 0.5
    textedit_activation="$("$ACTIVATE_APP" --click TextEdit 2>&1)" || true
    if [[ "$textedit_activation" == *"frontmost: loginwindow"* ]]; then
        echo "  FAIL  screen is locked; unlock the console before the GUI audit"
        FAIL=1
        break
    fi
    "$SLEEP" 0.2
    textedit_frontmost="$("$OSASCRIPT" \
        -e 'with timeout of 10 seconds' \
        -e 'tell application "System Events" to get frontmost of process "TextEdit"' \
        -e 'end timeout' 2>&1)"
    [ "$textedit_frontmost" = true ] && break
done
if [ "$textedit_frontmost" = true ]; then
    echo "  ok    TextEdit can become frontmost"
else
    echo "  FAIL  TextEdit can become frontmost: property is $textedit_frontmost"
    [ -n "$textedit_activation" ] && echo "  TextEdit activation helper: $textedit_activation"
    textedit_seen="$("$OSASCRIPT" \
        -e 'tell application "System Events" to exists process "TextEdit"' 2>&1)"
    echo "  TextEdit visible to System Events: $textedit_seen"
    echo "  Close permission prompts and other modal dialogs."
    FAIL=1
fi

if [ "$FAIL" -ne 0 ]; then
    echo "GUI preflight failed. Resolve the failed checks above before running."
    echo "For grant failures, enable Terminal under Accessibility and enable System"
    echo "Events and TextEdit under Automation, then quit and reopen Terminal."
    exit 1
fi
