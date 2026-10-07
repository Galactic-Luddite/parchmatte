#!/usr/bin/env bash
# Checks an expoprobe timeline (window-cover mode, target resting at <home>):
# the target's cover is never re-created mid-overview (no Parchmatte cover
# window appears that wasn't there in the first sample), is never shown
# (alpha >= 0.5) away from <home>, and is hidden while the overview is up.
# Usage: expo_check.sh <log> [home]   home default "200,150 800x600"
HOME_RECT="${2:-200,150 800x600}"
awk -v home="$HOME_RECT" '
/^t=/ { samples++; dock = 0; next }
/ Dock .*L=20/ { dock = 1; next }
/ Parchmatte / && !/L=102/ {
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
