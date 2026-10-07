#!/usr/bin/env bash
# Validates a results/<run-id>/envelope.json and exports it to an internal
# experiment tracker (owner-only infrastructure, not required to build or
# test Parchmatte). Not usable outside the owner's environment.
#
# Usage: Tests/Harness/export_run.sh <results/run-id dir>
# Requires TRACKER_TOOL_DIR, TRACKER_URI, TRACKER_AUTH_FILE and
# TRACKER_SPOOL_DIR in the environment.
set -euo pipefail
RUN="$(cd "$1" && pwd)"
: "${TRACKER_TOOL_DIR:?set TRACKER_TOOL_DIR}" "${TRACKER_URI:?set TRACKER_URI}"
: "${TRACKER_AUTH_FILE:?set TRACKER_AUTH_FILE}" "${TRACKER_SPOOL_DIR:?set TRACKER_SPOOL_DIR}"
AUTH="$TRACKER_AUTH_FILE"
SPOOL="$TRACKER_SPOOL_DIR"

cd "$TRACKER_TOOL_DIR"
python3 -m mm_core.experiments validate "$RUN/envelope.json" --run-root "$RUN" --json
python3 -m mm_core.experiments export "$RUN/envelope.json" --run-root "$RUN" \
    --tracking-uri "$TRACKER_URI" --auth-file "$AUTH" \
    --server-version 3.8.1 --spool-root "$SPOOL" --json \
    | python3 -c 'import json,sys; r=json.load(sys.stdin)["receipts"][0]; print("state", r["state"], "experiment", r["experiment_id"], "runs", len(r["run_ids"]))'
