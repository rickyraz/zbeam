#!/bin/sh
# Test-owned custom service; the supplied erl may be a pinned Docker wrapper.
set -eu
erl_bin=${1:?ERL required}
bin=${2:?CUSTOM_WORKER required}
label=${3:?LABEL required}
name="custom_${label}_$$"
log=$(mktemp)
pid=
cleanup() {
    status=$?
    [ "$status" -eq 0 ] || { printf '\ncustom-worker output:\n' >&2; cat "$log" >&2; }
    [ -z "$pid" ] || { kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; }
    rm -f "$log"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
sh "$(dirname "$0")/ensure_epmd.sh"
"$bin" serve-custom "$name" zbeam_test_cookie >"$log" 2>&1 &
pid=$!
tries=0
until grep -q '^registered ' "$log"; do
    kill -0 "$pid"
    tries=$((tries + 1)); [ "$tries" -lt 100 ] || exit 1
    sleep 0.1
done
timeout 45 "$erl_bin" +S 2:2 -noshell -name "ccs_${label}_$$@127.0.0.1" -setcookie zbeam_test_cookie -eval \
  "N=list_to_atom(\"$name@127.0.0.1\"),true=net_kernel:connect_node(N),
   Call=fun(To,Cmd)->R=make_ref(),To!{self(),R,Cmd},
     receive {R,V}->V after 5000->error({custom_timeout,Cmd}) end end,
   Endpoint={zbeam_workers,N},
   {ok,A}=Call(Endpoint,{discover,a}),{ok,B}=Call(Endpoint,{discover,b}),
   N=node(A),N=node(B),true=(A=/=B),
   {ok,<<>>}=Call(A,{call,<<>>}),{ok,<<\"ABC\">>}=Call(A,{call,<<\"abc\">>}),
   Max=binary:copy(<<97>>,65536),Upper=binary:copy(<<65>>,65536),
   {ok,Upper}=Call(B,{call,Max}),{error,bad_request}=Call(A,{hash,<<\"abc\">>}),
   true=monitor_node(N,true),true=erlang:disconnect_node(N),
   receive {nodedown,N}->ok after 5000->error(no_disconnect) end,
   true=net_kernel:connect_node(N),{ok,A}=Call(Endpoint,{discover,a}),{ok,B}=Call(Endpoint,{discover,b}),
   M=erlang:monitor(process,A),{error,handler_failed}=Call(A,{call,binary:copy(<<97>>,65537)}),
   receive {'DOWN',M,process,A,handler_failed}->ok after 5000->error(no_handler_down) end,
   {error,noproc}=Call(Endpoint,{discover,a}),{ok,<<\"LIVE\">>}=Call(B,{call,<<\"live\">>}),
   MB=erlang:monitor(process,B),ok=Call(B,stop),
   receive {'DOWN',MB,process,B,normal}->ok after 5000->error(no_stop_down) end,
   {error,noproc}=Call(Endpoint,{discover,b}),
   io:format(\"PASS custom binary call reconnect handler-failure sibling stop~n\"),halt()."
kill -0 "$pid"
echo "PASS $label custom compiled-handler profile"
