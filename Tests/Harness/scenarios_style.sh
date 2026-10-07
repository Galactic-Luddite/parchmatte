#!/usr/bin/env bash
# Per-window style (C): two TextEdit window covers with different textures,
# lamps and strength must each show their own look (pixel sample), keep it
# when the global style changes, and keep it through move/resize and full
# screen. Relaunches the app with known preferences and restores the user's
# preferences afterwards. Needs Screen Recording for the terminal (screencapture).
# Usage: Tests/Harness/scenarios_style.sh [path/to/Parchmatte.app]
set -uo pipefail
source "$(dirname "$0")/lib.sh"
APP=${1:-"$HARNESS/../../dist/Parchmatte.app"}
DOMAIN=com.galacticluddite.parchmatte
[ -x "$BIN/pixmean" ] && [ "$BIN/pixmean" -nt "$HARNESS/pixmean.swift" ] || swiftc -O "$HARNESS/pixmean.swift" -o "$BIN/pixmean"
BACKUP="$(mktemp -d)/prefs.bak"
defaults export "$DOMAIN" "$BACKUP"

relaunch() {
    pkill -x Parchmatte; sleep 1
    open "$APP"; sleep 2
}
# A centre patch of each window (points, top-left origin).
A="300 300 200 150"
B="1000 300 200 150"
sample() { "$BIN/pixmean" $1; }
warm() { local r g b; read -r r g b <<< "$1"; [ $((r - b)) -gt "$2" ]; }
neutral() { local r g b; read -r r g b <<< "$1"; [ $((r - b)) -lt 8 ] && [ $((b - r)) -lt 8 ]; }
close_to() {  # close_to "<r g b>" "<r g b>" tolerance
    local r1 g1 b1 r2 g2 b2; read -r r1 g1 b1 <<< "$1"; read -r r2 g2 b2 <<< "$2"
    local d=$(( (r1 > r2 ? r1 - r2 : r2 - r1) + (g1 > g2 ? g1 - g2 : g2 - g1) + (b1 > b2 ? b1 - b2 : b2 - b1) ))
    echo "delta=$d ($1 vs $2)"; [ "$d" -le "$3" ]
}
differs() { ! close_to "$@"; }
darker() {  # darker "<r g b>" "<r g b>" by
    local r1 g1 b1 r2 g2 b2; read -r r1 g1 b1 <<< "$1"; read -r r2 g2 b2 <<< "$2"
    echo "$1 vs $2"; [ $(( (r2 + g2 + b2) - (r1 + g1 + b1) )) -gt "$3" ]
}

# Known global style: chalkboard at 50%, no lamp, crisp; window covers only.
pkill -x Parchmatte; sleep 1
defaults write "$DOMAIN" wholeScreen -bool false
defaults write "$DOMAIN" hideFromScreenshots -bool false
defaults write "$DOMAIN" texture chalkboard
defaults write "$DOMAIN" opacity -float 0.5
defaults write "$DOMAIN" lamp off
defaults write "$DOMAIN" glow medium
defaults write "$DOMAIN" softness -float 0
open "$APP"; sleep 2

ensure_textedit
open_textedit_window "A" 100 150 700 650
open_textedit_window "B" 800 150 1400 650
sleep 1
base=$(sample "$A")
echo "baseline $base"

# Cover A with the global style.
textedit 'set index of window 2 to 1' >/dev/null; sleep 0.5
hotkey 35; sleep 0.8   # ⌃⌥P on A
a1=$(sample "$A")
expect "S1 A shows chalkboard at 50%" darker "$a1" "$base" 8

# B is in front with no cover: the keys change the global style.
textedit 'set index of window 2 to 1' >/dev/null; sleep 0.5
hotkey 37; hotkey 37                              # ⌃⌥L: off -> candlelight -> late night
for i in 1 2 3 4 5 6 7; do hotkey 125; done       # ⌃⌥↓ ×7: 50% -> 15%
hotkey 17                                         # ⌃⌥T: chalkboard -> linen
sleep 0.5
expect "S2 A unchanged by global changes" close_to "$(sample "$A")" "$a1" 6
hotkey 35; sleep 0.8   # ⌃⌥P on B: inherits late night / linen / 15%
b1=$(sample "$B")
expect "S3 B warm (late-night lamp)" warm "$b1" 15
expect "S3 A still neutral" neutral "$(sample "$A")"

# B is covered and in front: the keys change B only.
hotkey 126; hotkey 126; hotkey 37; sleep 0.5      # ⌃⌥↑ ×2 and ⌃⌥L (late night -> reading lamp) on B
expect "S4 B changed by its own keys" differs "$(sample "$B")" "$b1" 15
expect "S4 A unchanged by B's keys" close_to "$(sample "$A")" "$a1" 6
b2=$(sample "$B")

# Move/resize A; full screen B.
textedit 'set bounds of window 2 to {150, 200, 800, 700}' >/dev/null; sleep 1
expect "S5 A keeps its style after move" close_to "$(sample "$A")" "$a1" 8
osascript -e 'tell application "System Events" to tell process "TextEdit" to set value of attribute "AXFullScreen" of window 1 to true'
sleep 3
expect "S6 B keeps its style in full screen" close_to "$(sample "900 500 200 150")" "$b2" 10
osascript -e 'tell application "System Events" to tell process "TextEdit" to set value of attribute "AXFullScreen" of window 1 to false'
sleep 3
expect "S6 B keeps its style after full screen" close_to "$(sample "$B")" "$b2" 8

textedit_reset
sleep 4
pkill -x Parchmatte; sleep 1
defaults import "$DOMAIN" "$BACKUP"
open "$APP"
osascript -e 'tell application "TextEdit" to quit saving no' >/dev/null 2>&1
echo "style: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
