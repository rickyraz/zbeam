#!/bin/sh
# Daemonization can return before EPMD accepts the native peer's first connection.
set -eu
if timeout -k 1 5 sh -ec '
    # Keep the supervised shell alive until KILL can also reach a TERM-resistant probe.
    trap : TERM
    epmd -daemon
    until epmd -names >/dev/null 2>&1; do sleep 0.05 || :; done
'; then
    exit 0
else
    status=$?
    echo "FAIL EPMD startup/readiness (status $status)" >&2
    exit "$status"
fi
