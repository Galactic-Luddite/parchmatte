#!/usr/bin/env bash
# Preferences fuzz (security plan S5): for every key, write each bad value,
# launch the debug build (which uses the separate "Parchmatte" defaults
# domain, never the user's), and fail if the process doesn't survive.
#
# Usage: Tests/Harness/fuzz_prefs.sh    (run `swift build` first)
set -uo pipefail
cd "$(dirname "$0")/../.."

BIN=.build/debug/Parchmatte
DOMAIN=Parchmatte
[ -x "$BIN" ] || { echo "build first: swift build"; exit 2; }

keys=(wholeScreen opacity softness texture lamp glow lampStrength orientation schedule customStartMinutes
      customEndMinutes pauseOnBattery hideFromScreenshots disabledDisplays excludedApps
      restackWatchHz)
values=(
    "-string banana"
    "-float 1e308"
    "-float -1e308"
    "-float nan"
    "-float inf"
    "-int -2147483648"
    "-int 2147483647"
    "-bool true"
    "-array a b c"
    "-dict k v"
    # Two distinct keys longer than 256 characters sharing their first 256:
    # a truncating reader would see a duplicate key (review C1).
    "-dict $(printf 'A%.0s' $(seq 1 300)) v1 $(printf 'A%.0s' $(seq 1 300))B v2"
    "-string $(printf 'x%.0s' $(seq 1 5000))"
)

pass=0 fail=0
for key in "${keys[@]}"; do
    for value in "${values[@]}"; do
        defaults delete "$DOMAIN" >/dev/null 2>&1
        # shellcheck disable=SC2086
        defaults write "$DOMAIN" "$key" $value 2>/dev/null
        "$BIN" >/dev/null 2>&1 &
        pid=$!
        sleep 1.2
        if kill -0 "$pid" 2>/dev/null; then
            pass=$((pass + 1))
            kill "$pid"; wait "$pid" 2>/dev/null
        else
            fail=$((fail + 1))
            echo "CRASH: $key = ${value:0:40}"
        fi
    done
done
defaults delete "$DOMAIN" >/dev/null 2>&1
echo "fuzz: $pass survived, $fail crashed"
[ "$fail" -eq 0 ]
