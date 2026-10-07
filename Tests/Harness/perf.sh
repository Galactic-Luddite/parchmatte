#!/usr/bin/env bash
# Performance sampler (test plan section H): average CPU %, idle wake-ups/s and
# resident memory of Parchmatte over N seconds.
#
# Usage: Tests/Harness/perf.sh [seconds] [label]
set -uo pipefail
secs="${1:-20}"; label="${2:-run}"
pid="$(pgrep -x Parchmatte)" || { echo "Parchmatte is not running"; exit 2; }

# top in logging mode: one sample per second; the first sample has no deltas.
top -l $((secs + 1)) -s 1 -pid "$pid" -stats pid,cpu,idlew,mem 2>/dev/null \
    | awk -v label="$label" -v pid="$pid" '
        $1 == pid { n++; if (n > 1) { cpu += $2; wake += $3; mem = $4; k++ } }
        END { if (k) printf "%s: cpu_avg=%.2f%% idle_wakeups_avg=%.1f/s mem=%s samples=%d\n",
                             label, cpu / k, wake / k, mem, k }'
