#!/usr/bin/env bash
# Overlap: a cover rests one level above normal windows while nothing
# overlaps its window, so this checks that windows which do come over the
# covered window, from the same app and from another app, show no paper
# (the cover is stacked under them), and that clicking the covered window
# back to the front puts its cover straight back over it.
# Usage: Tests/Harness/overlap_run.sh
set -uo pipefail
source "$(dirname "$0")/lib.sh"
for t in click zorder covers check_cover activate_app; do
    [ -x "$BIN/$t" ] && [ "$BIN/$t" -nt "$HARNESS/$t.swift" ] || swiftc -O "$HARNESS/$t.swift" -o "$BIN/$t" || exit 2
done
was_whole=$(whole_screen && echo on || echo off)
set_whole_screen off
ensure_textedit
# A cover left by a closed document lingers 3 s and would re-attach to a
# new window in the same place, which the hotkey would then toggle off.
sleep 3.5
open_textedit_window "A" 200 150 1000 750 || true
# A document opened while TextEdit was still quitting lands at a default
# size; place it again before covering it.
textedit 'set bounds of window 1 to {200, 150, 1000, 750}' >/dev/null; sleep 0.5
cover_front || { echo "cover did not land"; exit 1; }
# Front-to-back index of the first matching line of zorder output.
zindex() {  # zindex <owner> <rect prefix>
    "$BIN/zorder" TextEdit Finder | awk -v o="$1" -v r="$2" '$2 == o && index($4, r) == 1 { print $1; exit }'
}
# under <owner> [rect]: the cover over A is stacked under that owner's
# first (frontmost) window.
under() { local c w; c=$(zindex Parchmatte 200,150); w=$(zindex "$1" "${2:-}"); [ -n "$c" ] && [ -n "$w" ] && [ "$c" -gt "$w" ]; }
# over_a: the cover is stacked directly over A.
over_a() { local c w; c=$(zindex Parchmatte 200,150); w=$(zindex TextEdit 200,150); [ -n "$c" ] && [ -n "$w" ] && [ "$c" -lt "$w" ]; }

# Same app: a second document in front, overlapping.
textedit 'make new document with properties {text:"B"}' >/dev/null; sleep 0.5
textedit 'set bounds of window 1 to {600, 400, 1400, 1000}' >/dev/null; sleep 1
"$BIN/zorder" TextEdit Finder
expect "O1 same-app window over the covered one has no paper" under TextEdit 600,400
# Click the covered window: it comes to the front, its cover with it.
"$BIN/click" 300 300; sleep 0.6
"$BIN/zorder" TextEdit Finder
expect "O2 covered window clicked back to front is covered" "$BIN/check_cover" TextEdit
expect "O3 cover stacked over the covered window after the click" over_a
# Close B only; A stays covered for the next part.
textedit 'close (every document whose text starts with "B") saving no' >/dev/null 2>&1; sleep 0.5

# Another app: a Finder window in front, overlapping.
osascript -e 'tell application "Finder" to make new Finder window' >/dev/null 2>&1; sleep 0.8
osascript -e 'tell application "Finder" to set bounds of front Finder window to {600, 400, 1400, 1000}' >/dev/null 2>&1
bring_front Finder; sleep 1
"$BIN/zorder" TextEdit Finder
expect "O4 other-app window over the covered one has no paper" under Finder
"$BIN/click" 300 300; sleep 0.8
"$BIN/zorder" TextEdit Finder
expect "O5 covered window clicked over Finder is covered" "$BIN/check_cover" TextEdit
expect "O6 cover stacked over the covered window after the click" over_a
osascript -e 'tell application "Finder" to close front Finder window' >/dev/null 2>&1
bring_front TextEdit; hotkey 35; sleep 0.5
textedit_reset
osascript -e 'tell application "TextEdit" to quit saving no' >/dev/null 2>&1
set_whole_screen "$was_whole"
echo "overlap: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
