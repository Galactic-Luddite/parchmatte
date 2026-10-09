#!/usr/bin/env bash
# Checks an expoprobe timeline (window-cover mode, target resting at <home>):
# the target's cover is never re-created mid-overview (no Parchmatte cover
# window appears that wasn't there in the first sample), is never shown
# (alpha >= 0.5) away from <home>, and is hidden while the overview is up.
# With --whole the subject is the display-sized screen cover (layer 102)
# instead: it is never shown away from its display frame (the window server
# shrinks it into a tile otherwise, issue #7) and is hidden while the
# overview is up.
# Usage: expo_check.sh <log> [home]           home default "200,150 800x600"
#        expo_check.sh --whole <log> [home]   home default "0,0 1920x1080"
WHOLE=0
if [ "${1:-}" = --whole ]; then WHOLE=1; shift; fi
if [ "$WHOLE" = 1 ]; then HOME_RECT="${2:-0,0 1920x1080}"; else HOME_RECT="${2:-200,150 800x600}"; fi
awk -v home="$HOME_RECT" -v whole="$WHOLE" '
/^t=/ { samples++; dock = 0; next }
/ Dock .*L=20/ { dock = 1; next }
/ Parchmatte / && ((whole == 1 && /L=102/) || (whole == 0 && !/L=102/)) {
    id = $3; a = substr($5, 3) + 0; r = $6 " " $7
    if (samples == 1) { first[id] = 1; if (r == home) mine = id }
    else if (!(id in first)) { if (!(id in extra)) extras++; extra[id] = 1 }
    if (id != mine) next
    if (a >= 0.5 && r != home) away++
    if (dock && a == 0) hidden++
}
END {
    printf "cover=%s newCovers=%d shownAway=%d hiddenSamples=%d\n", mine, extras, away, hidden
    exit !(mine != "" && extras == 0 && away == 0 && hidden > 0)
}' "$1"
