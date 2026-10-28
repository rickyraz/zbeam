#!/bin/sh
# Opt-in Linux example checks. No failure injection is compiled into zbeam.
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
for program in elixir python3 epmd kill; do command -v "$program" >/dev/null; done
timeout 15 elixir --erl '+S 2:2' "$root/tests/interop/two_worker_admission_test.exs"
python3 "$root/tests/integration/worker_guard_test.py"
sh "$root/scripts/interop/ensure_epmd.sh"
timeout 90 elixir --erl '+S 2:2' --name "recovery_$$@127.0.0.1" --cookie zbeam_test_cookie \
    "$root/tests/interop/worker_recovery_test.exs" "$bin" "$fault_bin"
timeout 15 elixir --erl '+S 2:2' --name "example_$$@127.0.0.1" --cookie zbeam_test_cookie \
    "$root/examples/monitored_worker.exs" "$bin"
# Own a foreground EPMD on a private port; never kill the shared developer daemon.
epmd -port "$port" -relaxed_command_check >"$logs/epmd" 2>&1 &
private_pid=$!
tries=0
until epmd -port "$port" -names >/dev/null 2>&1; do
    kill -0 "$private_pid"
    tries=$((tries + 1)); [ "$tries" -lt 100 ] || exit 1
    sleep 0.05
done
kill -0 "$private_pid"
ONLY_EPMD=1 ERL_EPMD_PORT="$port" TEST_EPMD_PID="$private_pid" \
    timeout 30 elixir --erl '+S 2:2 -start_epmd false' --name "epmd_recovery_$$@127.0.0.1" --cookie zbeam_test_cookie \
    "$root/tests/interop/worker_recovery_test.exs" "$bin" "$fault_bin"
echo 'PASS bounded owner recovery and private EPMD loss'
