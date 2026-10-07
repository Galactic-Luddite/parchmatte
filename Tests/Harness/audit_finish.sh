#!/usr/bin/env bash
# Source after defining restore_prefs. The EXIT trap owns the final verdict so
# preference restoration is part of the audit's success criteria.
audit_finish() {
    local audit_rc=$?
    trap - EXIT
    restore_prefs || audit_rc=1
    if [ "$audit_rc" -eq 0 ]; then
        echo "AUDIT PASSED"
    fi
    exit "$audit_rc"
}
