#!/usr/bin/env bash
# Runs every automated audit suite against the running Parchmatte build and
# writes Tests/Harness/results/<run-id>/: one log per suite plus
# envelope.json (an internal experiment-tracker envelope, see make_envelope.py).
#
# Usage: Tests/Harness/run_audit.sh [flavor]     flavor: free (default) | store
# Needs: Parchmatte running, two desktops, TextEdit, System Events control.
# Uses the Mac for several minutes: it opens windows and switches desktops.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
FLAVOR="${1:-free}"
RUN_ID="parchmatte-$(date -u +%Y%m%dT%H%M%SZ)-$FLAVOR"
OUT="$HERE/results/$RUN_ID"
mkdir -p "$OUT"
STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

pgrep -x Parchmatte >/dev/null || { echo "start Parchmatte first"; exit 2; }
cd "$ROOT"

# Compile every probe before preflight; activate_app is itself part of the
# foreground check. These are fast, local binaries and remain gitignored.
mkdir -p "$HERE/bin"
for tool in activate_app check_cover screens probe screencovers covers click; do
    swiftc -O -o "$HERE/bin/$tool" "$HERE/$tool.swift" || exit 2
done

# Fail quickly when Terminal's TCC grants are missing instead of letting the
# first GUI suite accumulate two-minute Apple Event timeouts. This runs before
# preferences are captured or changed.
"$HERE/gui_preflight.sh" > "$OUT/gui-preflight.log" 2>&1
preflight_rc=$?
echo "exit=$preflight_rc" >> "$OUT/gui-preflight.log"
if [ "$preflight_rc" -ne 0 ]; then
    cat "$OUT/gui-preflight.log"
    echo "GUI PREFLIGHT FAILED"
    exit 2
fi
cat "$OUT/gui-preflight.log"

# Snapshot the user's settings; restore them (restarting the app) at the end,
# whatever the suites did.
APP_PATH="$(ps -o comm= -p "$(pgrep -x Parchmatte)" | sed -E 's|/Contents/MacOS/.*||')"
APP_EXE="$APP_PATH/Contents/MacOS/Parchmatte"
PREFS_SNAPSHOT="$OUT/.prefs-before.xml"
if ! "$APP_EXE" --audit-export-preferences > "$PREFS_SNAPSHOT" \
    || ! plutil -lint "$PREFS_SNAPSHOT" >/dev/null 2>&1; then
    echo "PREFERENCE BACKUP FAILED: signed app could not export a valid snapshot"
    exit 2
fi
restore_prefs() {
    pkill -x Parchmatte; sleep 1
    if "$APP_EXE" --audit-import-preferences < "$PREFS_SNAPSHOT" \
        && "$APP_EXE" --audit-export-preferences | cmp -s "$PREFS_SNAPSHOT" -; then
        : # Keep the snapshot until the app has restarted successfully.
    else
        echo "PREFERENCE RESTORE FAILED OR MISMATCHED: snapshot kept at $PREFS_SNAPSHOT" >&2
        return 1
    fi
    if ! open "$APP_PATH"; then
        echo "PREFERENCE RESTORE FAILED: app restart failed; snapshot kept at $PREFS_SNAPSHOT" >&2
        return 1
    fi
    rm -f "$PREFS_SNAPSHOT"
}
source "$HERE/audit_finish.sh"
trap audit_finish EXIT

# A running process is not sufficient: wait for the hotkeys and cover manager
# to respond before attributing any failures to the measured suites.
"$HERE/app_readiness.sh" > "$OUT/app-readiness.log" 2>&1
readiness_rc=$?
echo "exit=$readiness_rc" >> "$OUT/app-readiness.log"
if [ "$readiness_rc" -ne 0 ]; then
    cat "$OUT/app-readiness.log"
    echo "APP READINESS FAILED"
    exit 2
fi
cat "$OUT/app-readiness.log"

FAILED=()
run() {  # run <suite> <command...>; records a failing suite
    local suite="$1"; shift
    echo "== $suite"
    "$@" > "$OUT/$suite.log" 2>&1
    local rc=$?
    echo "exit=$rc" >> "$OUT/$suite.log"
    tail -2 "$OUT/$suite.log"
    [ "$rc" -eq 0 ] || FAILED+=("$suite")
    return "$rc"
}

run windows     "$HERE/scenarios_windows.sh"
run expose      "$HERE/scenarios_expose.sh"
run adopt       "$HERE/scenarios_adopt.sh"
run screenshot  "$HERE/scenarios_screenshot.sh"
run menuclick   "$HERE/menu_click_run.sh"
run fullscreen  "$HERE/scenarios_fullscreen.sh"
run spaces      "$HERE/scenarios_spaces.sh"
run drag        "$HERE/scenarios_drag.sh"
run perf        "$HERE/scenarios_perf.sh"
run netwatch    "$HERE/netwatch.sh" 30
run softness    swift "$HERE/softness_check.swift" Sources/Parchmatte/Textures/linen.png
run layouts     swift "$HERE/layouts.swift"
swift build >/dev/null 2>&1 || FAILED+=("swift-build")
run displays    "$HERE/displays_key.sh"    # quits the app; the exit trap restarts it
run fuzz        "$HERE/fuzz_prefs.sh"

ENDED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
python3 "$HERE/make_envelope.py" "$OUT" "$RUN_ID" "$FLAVOR" "$STARTED" "$ENDED" > "$OUT/envelope.json" \
    && echo "envelope: $OUT/envelope.json" || FAILED+=("envelope")
if [ "${#FAILED[@]}" -gt 0 ]; then
    echo "AUDIT FAILED: ${FAILED[*]}"
    exit 1
fi
