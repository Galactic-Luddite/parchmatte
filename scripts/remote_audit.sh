#!/usr/bin/env bash
# Runs the automated audit (Tests/Harness/run_audit.sh) on another Mac over
# SSH and copies the results back, so this machine's screen stays free.
#
# The harness drives the other Mac's desktop for several minutes (it opens
# windows, swipes between desktops and opens Mission Control), so that Mac
# needs a display, a second desktop, and the SSH user logged in at the
# console in the foreground. Keystrokes go to whoever is in front.
#
# Usage: scripts/remote_audit.sh [--check] [--ref <git ref>] [--flavor free|store] [--resume-state <path>] <host>
#   host       SSH host (or set PARCHMATTE_HOST)
#   --check    preflight only: tools, console user, screen lock, checkout
#   --ref      what to test; default: this checkout's HEAD, which must be pushed
#   --flavor   free (default): builds scripts/build.sh on the host
#              store: launches an installed store build instead
#                     (PARCHMATTE_STORE_APP, default /Applications/Parchmatte.app)
#   --resume-state  reconnect to an audit state path printed by this script
# Env:   PARCHMATTE_REMOTE_DIR   checkout on the host (default: "parchmatte" under the remote home directory)
#        PARCHMATTE_TIMEOUT      seconds to wait for the audit (default 2400)
#        PARCHMATTE_LOCAL_RESULTS_DIR  copied-result destination (default Tests/Harness/results)
#
# First run on a new host: on that Mac, run Tests/Harness/run_audit.sh once by
# hand from Terminal and allow the Accessibility, Automation (System Events,
# TextEdit) and Screen Recording prompts. Those grants belong to Terminal, so
# this script starts the audit in a new Terminal window on the host rather
# than in the SSH session, where the prompts never appear and the keystrokes
# are refused.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CHECK_ONLY=0 REF="" FLAVOR=free RESUME_STATE="" HOST="${PARCHMATTE_HOST:-}"
while [ $# -gt 0 ]; do
    case "$1" in
        --check) CHECK_ONLY=1 ;;
        --ref) REF="$2"; shift ;;
        --flavor) FLAVOR="$2"; shift ;;
        --resume-state) RESUME_STATE="$2"; shift ;;
        -h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "unknown option: $1" >&2; exit 2 ;;
        *) HOST="$1" ;;
    esac
    shift
done
[ -n "$HOST" ] || { echo "usage: $0 [--check] [--ref REF] [--flavor free|store] <host>" >&2; exit 2; }
case "$FLAVOR" in free|store) ;; *) echo "flavor must be free or store" >&2; exit 2 ;; esac
if [ -n "$RESUME_STATE" ]; then
    case "$RESUME_STATE" in */parchmatte-audit.*) ;;
        *) echo "resume state must match */parchmatte-audit.*" >&2; exit 2 ;;
    esac
fi
[ -n "$REF" ] || REF="$(git -C "$ROOT" rev-parse HEAD)"

REMOTE_DIR="${PARCHMATTE_REMOTE_DIR:-parchmatte}"  # relative paths resolve under the remote $HOME
STORE_APP="${PARCHMATTE_STORE_APP:-/Applications/Parchmatte.app}"
TIMEOUT="${PARCHMATTE_TIMEOUT:-2400}"
LOCAL_RESULTS_DIR="${PARCHMATTE_LOCAL_RESULTS_DIR:-$ROOT/Tests/Harness/results}"
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=10 "$HOST")

# Every remote step is one `bash -s` with the parameters passed as arguments,
# so nothing is interpolated into remote shell text. Each script that takes
# the checkout path expands a leading ~ itself (SSH passes it literally).
remote() {
    # Some SSH servers incorrectly report exit-status 0 even when the remote
    # command fails. Carry the Bash status in a final output marker and fail
    # closed if the marker is missing or malformed.
    local output transport_rc remote_rc marker=$'\n__PARCHMATTE_REMOTE_EXIT__='
    output="$({ printf '%s\n' 'trap '\''printf "\n__PARCHMATTE_REMOTE_EXIT__=%s\n" "$?"'\'' EXIT'; cat; } \
        | "${SSH[@]}" bash -s -- "$@" 2>&1)"
    transport_rc=$?
    if [ "$transport_rc" -ne 0 ]; then
        printf '%s\n' "$output" >&2
        return "$transport_rc"
    fi
    case "$output" in
        *"$marker"*)
            remote_rc="${output##*"$marker"}"
            output="${output%"$marker"*}"
            [ -z "$output" ] || printf '%s\n' "$output"
            case "$remote_rc" in
                ''|*[!0-9]*) echo 'invalid remote exit status' >&2; return 1 ;;
                *) return "$remote_rc" ;;
            esac
            ;;
        *)
            printf '%s\n' "$output" >&2
            echo 'remote exit status missing' >&2
            return 1
            ;;
    esac
}

# macOS ships Bash 3.2, which misparses a here-document inside a quoted command
# substitution when the document contains another here-document or a case
# pattern. Capture remote stdout in a file so every remote script remains a
# normal top-level here-document. Reuse one file for the polling loop.
CAPTURE_FILE="$(mktemp "${TMPDIR:-/tmp}/parchmatte-remote.XXXXXX")" || exit 1
trap 'rm -f "$CAPTURE_FILE"' EXIT
remote_capture() {
    : > "$CAPTURE_FILE" || return 1
    remote "$@" > "$CAPTURE_FILE"
}

echo "==> Preflight on $HOST"
remote "$REMOTE_DIR" "$FLAVOR" "$STORE_APP" <<'EOF'
set -u
dir=$1; case $dir in "~"*) dir="$HOME${dir#\~}" ;; /*) ;; *) dir="$HOME/$dir" ;; esac; flavor=$2; store_app=$3
fail=0
ok()   { echo "  ok    $*"; }
warn() { echo "  WARN  $*"; }
bad()  { echo "  FAIL  $*"; fail=1; }

[ "$(uname)" = Darwin ] && ok "macOS $(sw_vers -productVersion)" || bad "not macOS"
xcode-select -p >/dev/null 2>&1 && ok "developer tools: $(xcode-select -p)" \
    || bad "no developer tools; run: xcode-select --install"
swift --version >/dev/null 2>&1 && ok "swift: $(swift --version 2>&1 | head -1)" || bad "swift not usable"

console="$(stat -f %Su /dev/console 2>/dev/null)"
if [ "$console" = "$(whoami)" ]; then ok "console user is $console"
else bad "console user is '$console', SSH user is '$(whoami)'; the harness's keystrokes would go to the wrong session. Log in as $(whoami) on the display"; fi

session_plist="$(mktemp "${TMPDIR:-/tmp}/parchmatte-console-session.XXXXXX")"
if ! ioreg -n Root -d1 -a > "$session_plist" 2>/dev/null \
        || ! plutil -lint "$session_plist" >/dev/null 2>&1; then
    bad "could not determine whether the screen is locked"
else
    # On macOS 15 the lock key is present with value true while locked, but is
    # omitted entirely after unlock. Treat a valid session plist without the
    # key as unlocked; never treat malformed or missing ioreg output that way.
    if ! locked="$(plutil -extract IOConsoleUsers.0.CGSSessionScreenIsLocked raw -o - "$session_plist" 2>/dev/null)"; then
        locked=""
    fi
    case "$locked" in
        true) bad "screen is locked; unlock it (and turn off auto-lock for this user)" ;;
        false|'') ok "screen not locked" ;;
        *) bad "could not determine whether the screen is locked" ;;
    esac
fi
rm -f "$session_plist"

[ -d /System/Applications/Utilities/Terminal.app ] && ok "Terminal present" || bad "Terminal.app missing"
[ -d /System/Applications/TextEdit.app ] && ok "TextEdit present" || bad "TextEdit.app missing"

if git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then ok "checkout at $dir ($(git -C "$dir" remote get-url origin 2>/dev/null))"
else bad "no checkout at $dir; clone the repository there (or set PARCHMATTE_REMOTE_DIR)"; fi

if [ "$flavor" = store ]; then
    [ -d "$store_app" ] && ok "store build at $store_app" || bad "no store build at $store_app (set PARCHMATTE_STORE_APP)"
fi
echo "  note  the harness needs at least two desktops on the main display; that can't be checked from here"
exit $fail
EOF
rc=$?
if [ $rc -ne 0 ]; then echo "preflight failed"; exit 1; fi
[ "$CHECK_ONLY" = 1 ] && exit 0

if [ -n "$RESUME_STATE" ]; then
    STATE_DIR="$RESUME_STATE"
    echo "==> Resuming audit at $HOST:$STATE_DIR"
else
echo "==> Checking out $REF and building ($FLAVOR)"
if ! remote "$REMOTE_DIR" "$REF" "$FLAVOR" <<'EOF'
set -eu
dir=$1; case $dir in "~"*) dir="$HOME${dir#\~}" ;; /*) ;; *) dir="$HOME/$dir" ;; esac; ref=$2; flavor=$3
cd "$dir"
if pgrep -x Parchmatte >/dev/null; then pkill -x Parchmatte; sleep 1; fi
git fetch --quiet origin
git rev-parse --verify --quiet "$ref^{commit}" >/dev/null \
    || git rev-parse --verify --quiet "origin/$ref^{commit}" >/dev/null \
    || { echo "ref $ref not found on origin; push it first" >&2; exit 1; }
git checkout --quiet --detach "$ref" 2>/dev/null || git checkout --quiet --detach "origin/$ref"
echo "at $(git rev-parse --short HEAD): $(git log -1 --format=%s)"
if [ "$flavor" = free ]; then
    build_log="${TMPDIR:-/tmp}/parchmatte-build.log"
    scripts/build.sh >"$build_log" 2>&1 || { tail -20 "$build_log"; exit 1; }
    echo "built dist/Parchmatte.app"
fi
# displays_key.sh and fuzz_prefs.sh run the debug binary.
swift build >/dev/null 2>&1 || { echo "swift build (debug) failed" >&2; exit 1; }
EOF
then echo "remote build failed"; exit 1; fi

echo "==> Starting the audit in a Terminal window on $HOST"
if ! remote_capture "$REMOTE_DIR" "$FLAVOR" "$STORE_APP" <<'EOF'
set -eu
dir=$1; case $dir in "~"*) dir="$HOME${dir#\~}" ;; /*) ;; *) dir="$HOME/$dir" ;; esac; flavor=$2; store_app=$3
state="$(mktemp -d "${TMPDIR:-/tmp}/parchmatte-audit.XXXXXX")"
app="$dir/dist/Parchmatte.app"; [ "$flavor" = store ] && app="$store_app"
# Terminal runs the file when it is opened with it. Everything the audit needs
# is inside this window, so it inherits Terminal's permission grants.
cat > "$state/run.command" <<CMD
#!/bin/bash
cd "$dir"
exec > >(tee "$state/audit.log") 2>&1
audit_tty=\$(tty)
caffeinate -dimsu -w \$\$ &
open "$app"; sleep 3
pgrep -x Parchmatte >/dev/null || { echo "Parchmatte did not start from $app"; echo 2 > "$state/done"; exit 2; }
Tests/Harness/run_audit.sh "$flavor"; rc=\$?
# run_audit.sh relaunches the app when it restores the user's preferences;
# don't leave paper on this Mac's screen after the run.
pkill -x Parchmatte
echo \$rc > "$state/done"
# A .command window otherwise remains at "Process completed" when Terminal's
# profile is configured not to close it. Close only this run's exact TTY.
(
    sleep 0.2
    osascript \
        -e 'on run argv' \
        -e 'set auditTTY to item 1 of argv' \
        -e 'tell application "Terminal"' \
        -e 'repeat with terminalWindow in windows' \
        -e 'repeat with terminalTab in tabs of terminalWindow' \
        -e 'if (tty of terminalTab) is auditTTY then' \
        -e 'if (count of tabs of terminalWindow) is not 1 then return' \
        -e 'close terminalWindow' \
        -e 'return' \
        -e 'end if' \
        -e 'end repeat' \
        -e 'end repeat' \
        -e 'end tell' \
        -e 'end run' \
        "\$audit_tty" >/dev/null 2>&1
) &
exit \$rc
CMD
chmod +x "$state/run.command"
open -a Terminal "$state/run.command"
echo "$state"
EOF
then echo "could not start the audit"; exit 1; fi
STATE_DIR="$(cat "$CAPTURE_FILE")"
[ -n "$STATE_DIR" ] || { echo "could not start the audit"; exit 1; }
echo "    state: $HOST:$STATE_DIR"
fi

echo "==> Waiting (timeout ${TIMEOUT}s)"
start=$(date +%s); shown=0
while :; do
    if ! remote_capture "$STATE_DIR" <<'EOF'
state=$1
if [ -f "$state/done" ]; then echo "done $(cat "$state/done")"; else echo "running"; fi
if [ -f "$state/audit.log" ]; then cat "$state/audit.log"; fi
exit 0
EOF
    then echo "could not poll the audit; it may still be running on $HOST (state: $STATE_DIR)"; exit 1; fi
    status="$(cat "$CAPTURE_FILE")"
    log="$(printf '%s\n' "$status" | tail -n +2)"
    total=0; [ -n "$log" ] && total=$(printf '%s\n' "$log" | wc -l | tr -d ' ')
    if [ "$total" -gt "$shown" ]; then
        printf '%s\n' "$log" | tail -n +"$((shown + 1))" | sed 's/^/    /'
        shown=$total
    fi
    case "$status" in done*) rc="${status%%$'\n'*}"; rc="${rc#done }"; break ;; esac
    if [ $(( $(date +%s) - start )) -ge "$TIMEOUT" ]; then
        echo "timed out; the audit may still be running on $HOST (log: $STATE_DIR/audit.log)"; exit 1
    fi
    sleep 20
done

echo "==> Copying results"
if remote_capture "$REMOTE_DIR" "$FLAVOR" <<'EOF'
dir=$1; case $dir in "~"*) dir="$HOME${dir#\~}" ;; /*) ;; *) dir="$HOME/$dir" ;; esac
ls -td "$dir"/Tests/Harness/results/parchmatte-*-"$2" 2>/dev/null | head -1
EOF
then RUN_DIR="$(cat "$CAPTURE_FILE")"
else RUN_DIR=""; echo "    could not locate results on $HOST"; fi
if [ -n "$RUN_DIR" ]; then
    mkdir -p "$LOCAL_RESULTS_DIR"
    scp -q -o BatchMode=yes -r "$HOST:$RUN_DIR" "$LOCAL_RESULTS_DIR/" \
        && echo "    $LOCAL_RESULTS_DIR/$(basename "$RUN_DIR")" \
        || echo "    copy failed; results are at $HOST:$RUN_DIR"
else
    echo "    no results folder found on $HOST"
fi
remote "$STATE_DIR" <<'EOF'
rm -rf "$1"
EOF
[ "${rc:-1}" = 0 ] && echo "AUDIT PASSED on $HOST" || echo "AUDIT FAILED on $HOST (exit $rc)"
exit "${rc:-1}"
