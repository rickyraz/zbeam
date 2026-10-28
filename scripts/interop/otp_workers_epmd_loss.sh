#!/bin/sh
# Run only inside an isolated network/PID namespace with a private EPMD on 4369.
set -eu
bin=${1:?ZBEAM required}
[ "${ZBEAM_ISOLATED_EPMD:-}" = 1 ] || { echo 'isolated network namespace required' >&2; exit 1; }
log=$(mktemp)
epmd_pid=
worker=
cleanup() {
    status=$?
    [ "$status" -eq 0 ] || { printf '\nproduction two-worker output:\n' >&2; cat "$log" >&2; }
    [ -z "$worker" ] || { kill "$worker" 2>/dev/null || true; wait "$worker" 2>/dev/null || true; }
    [ -z "$epmd_pid" ] || { kill "$epmd_pid" 2>/dev/null || true; wait "$epmd_pid" 2>/dev/null || true; }
    rm -f "$log"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
epmd -port 4369 -relaxed_command_check > /dev/null 2>&1 &
epmd_pid=$!
tries=0
until epmd -port 4369 -names >/dev/null 2>&1; do
    kill -0 "$epmd_pid"
    tries=$((tries + 1)); [ "$tries" -lt 100 ] || exit 1
    sleep 0.05
done
kill -0 "$epmd_pid"
"$bin" serve-workers isolated_workers zbeam_test_cookie >"$log" 2>&1 &
worker=$!
tries=0
until grep -q '^registered ' "$log"; do
    kill -0 "$worker"
    tries=$((tries + 1)); [ "$tries" -lt 100 ] || exit 1
    sleep 0.05
done
EPMD_PID=$epmd_pid timeout 20 erl +S 2:2 -noshell -name isolated_client@127.0.0.1 -setcookie zbeam_test_cookie -eval \
  'N=list_to_atom("isolated_workers@127.0.0.1"),
   true=net_kernel:connect_node(N),R=make_ref(),
   {zbeam_workers,N}!{self(),R,{discover,a}},
   P=receive {R,{ok,Pid}}->Pid after 5000->error(no_worker) end,
   true=monitor_node(N,true),M=erlang:monitor(process,P),
   os:cmd("kill -TERM "++os:getenv("EPMD_PID")),
   receive {nodedown,N}->ok after 5000->error(no_nodedown) end,
   Down=list_to_atom("DOWN"),
   receive {Down,M,process,P,noconnection}->ok after 5000->error(no_down) end,
   io:format("PASS production two-worker EPMD loss~n"),halt().'
if wait "$worker"; then echo 'FAIL worker survived EPMD loss' >&2; exit 1; fi
worker=
grep -q 'EpmdRegistrationLost' "$log"
wait "$epmd_pid" 2>/dev/null || true
epmd_pid=
