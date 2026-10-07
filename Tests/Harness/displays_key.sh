#!/usr/bin/env bash
# Displays menu keys by hardware UUID, not name (review C4). Runs the debug
# build (separate "Parchmatte" defaults domain, never the user's):
#  K1 toggling the first display stores a UUID;
#  K2 a name-keyed entry from builds 1-2 migrates to UUID keys on toggle.
#
# Usage: Tests/Harness/displays_key.sh    (run `swift build` first; quits
# any running Parchmatte and does not restart it)
set -uo pipefail
source "$(dirname "$0")/lib.sh"
ROOT="$(cd "$HARNESS/../.." && pwd)"
DBG="$ROOT/.build/debug/Parchmatte"
[ -x "$DBG" ] || { echo "build first: swift build"; exit 2; }
uuid_re='^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$'

click_first_display() {
    osascript -e 'tell application "System Events" to tell process "Parchmatte"
        click menu bar item 1 of menu bar 1
        delay 0.5
        click menu item "Displays" of menu 1 of menu bar item 1 of menu bar 1
        delay 0.4
        set target to menu item 1 of menu 1 of menu item "Displays" of menu 1 of menu bar item 1 of menu bar 1
        click target
    end tell'
}

[ -x "$BIN/screens" ] || swiftc -O -o "$BIN/screens" "$HARNESS/screens.swift" || exit 2
screen=$("$BIN/screens" | sed -n '1p')
[ -n "$screen" ] || { echo "could not read the first display"; exit 2; }
# `localizedName` can legitimately be empty on macOS 15 in a remote console
# session. That is also the value older builds stored, so keep it verbatim.
name=$(printf '%s\n' "$screen" | sed 's/^[0-9][0-9]* //; s/ frame=.*//')

pkill -x Parchmatte; sleep 1
defaults delete Parchmatte >/dev/null 2>&1
"$DBG" >/dev/null 2>&1 & sleep 2.5
click_first_display >/dev/null; sleep 0.5
expect "K1 toggle stores a UUID ($name)" bash -c "stored=\$(defaults read Parchmatte disabledDisplays | tr -d ' \"(),' | grep .); echo \$stored; grep -Eq '$uuid_re' <<< \"\$stored\""
pkill -x Parchmatte; sleep 1

# Legacy: the display disabled by name, as builds 1-2 stored it.
base="${name% (*}"
defaults delete Parchmatte >/dev/null 2>&1
defaults write Parchmatte disabledDisplays -array "$base"
"$DBG" >/dev/null 2>&1 & sleep 2.5
click_first_display >/dev/null; sleep 0.5
expect "K2 legacy name entry migrated" bash -c "v=\$(defaults read Parchmatte disabledDisplays); echo \$v; ! grep -qF '\"$base\"' <<< \"\$v\" && ! grep -qF ' $base,' <<< \"\$v\""
pkill -x Parchmatte; sleep 1
defaults delete Parchmatte >/dev/null 2>&1
echo "displays_key: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
