#!/bin/sh
# Own the guarded native child and a private EPMD; never stop the shared daemon.
set -eu
bin=${1:?ZBEAM required}
fault_bin=${2:?FAULT_FIXTURE required}
root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
logs=$(mktemp -d)
private_pid=
port=$((20000 + $$ % 30000))
cleanup() {
    [ -z "$private_pid" ] || { kill "$private_pid" 2>/dev/null || true; wait "$private_pid" 2>/dev/null || true; }
    rm -rf "$logs"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
sh "$root/scripts/interop/ensure_epmd.sh"
timeout 45 elixir --erl '+S 2:2' --name "m2_recovery_$$@127.0.0.1" --cookie zbeam_test_cookie \
    "$root/tests/interop/two_worker_recovery.exs" "$bin" "$fault_bin"
epmd -port "$port" -relaxed_command_check >"$logs/epmd" 2>&1 &
private_pid=$!
tries=0
until epmd -port "$port" -names >/dev/null 2>&1; do
    kill -0 "$private_pid"
    tries=$((tries + 1)); [ "$tries" -lt 100 ] || exit 1
    sleep 0.05
done
kill -0 "$private_pid"
M2_EPMD=1 ERL_EPMD_PORT="$port" TEST_EPMD_PID="$private_pid" \
    timeout 45 elixir --erl '+S 2:2 -start_epmd false' --name "m2_epmd_$$@127.0.0.1" --cookie zbeam_test_cookie \
    "$root/tests/interop/two_worker_recovery.exs" "$bin" "$fault_bin"
echo 'PASS two-worker process-loss no-replay and private EPMD loss'
