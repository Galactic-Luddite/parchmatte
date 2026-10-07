#!/usr/bin/env bash
# Performance scenarios (H1-H3): whole screen only; 1 window cover idle;
# 5 window covers idle; 1 window cover while its window is dragged.
# Leaves Paper Whole Screen as it found it.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
PERF="$HARNESS/perf.sh"

was_whole=$(whole_screen && echo on || echo off)

set_whole_screen on
"$PERF" 15 "H1 whole-screen only"

set_whole_screen off
ensure_textedit
open_textedit_window "P1" 100 100 700 500
cover_front
h2=$("$PERF" 15 "H2 one window cover, idle"); echo "$h2"
expect "H2 idle cover under 2% CPU" python3 -c "import re,sys; sys.exit(0 if float(re.search(r'cpu_avg=([0-9.]+)', '''$h2''').group(1)) < 2 else 1)"

# H0: snoozed (⌃⌥S) with a window cover, so nothing can show: no timer of
# ours may run but the 30 s schedule clock. top's idle-wakeup column is not a
# reliable per-second rate for an idle process, so assert on CPU time
# instead: over 15 s the app may use at most 30 ms (the clock firing once,
# at 10 ms resolution). Build 2's 10 Hz tracking used about 70 ms.
hotkey 1; sleep 2
pid=$(pgrep -x Parchmatte)
t0=$(ps -o time= -p "$pid" | tr -d ' ')
h0=$("$PERF" 15 "H0 snoozed, one window cover"); echo "$h0"
t1=$(ps -o time= -p "$pid" | tr -d ' ')
hotkey 1; sleep 1
secs() { python3 -c "import sys; p=sys.argv[1].split(':'); print(round(float(p[-1]) + 60 * float(p[-2] if len(p) > 1 else 0) + 3600 * float(p[-3] if len(p) > 2 else 0), 2))" "$1"; }
expect "H0 paused: <= 30 ms CPU in 15 s ($t0 -> $t1)" python3 -c "import sys; sys.exit(0 if $(secs "$t1") - $(secs "$t0") <= 0.03 + 1e-9 else 1)"

for i in 2 3 4 5; do
    open_textedit_window "P$i" $((100 + i * 60)) $((100 + i * 40)) $((700 + i * 60)) $((500 + i * 40))
    cover_front
done
"$PERF" 15 "H3 five window covers, idle"

# Drag: move the front window around continuously while sampling.
(
    for step in $(seq 1 60); do
        x=$((150 + (step % 20) * 20))
        textedit "set bounds of window 1 to {$x, 150, $((x + 600)), 550}"
        sleep 0.2
    done
) &
mover=$!
"$PERF" 12 "H3b five covers, one window moving"
wait "$mover"

textedit_reset
osascript -e 'tell application "TextEdit" to quit saving no' >/dev/null 2>&1
set_whole_screen "$was_whole"
echo "perf: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
