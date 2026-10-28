#!/bin/sh
# Test-owned M2b service; the supplied erl may be a pinned Docker wrapper.
set -eu
erl_bin=${1:?ERL required}
bin=${2:?ZBEAM required}
label=${3:?LABEL required}
name="workers_${label}_$$"
log=$(mktemp)
pid=
cleanup() {
    status=$?
    [ "$status" -eq 0 ] || { printf '\ntwo-worker output:\n' >&2; cat "$log" >&2; }
    [ -z "$pid" ] || { kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; }
    rm -f "$log"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
sh "$(dirname "$0")/ensure_epmd.sh"
"$bin" serve-workers "$name" zbeam_test_cookie >"$log" 2>&1 &
pid=$!
tries=0
until grep -q '^registered ' "$log"; do
    kill -0 "$pid"
    tries=$((tries + 1)); [ "$tries" -lt 100 ] || exit 1
    sleep 0.1
done
timeout 45 "$erl_bin" +S 2:2 -noshell -name "wcs_${label}_$$@127.0.0.1" -setcookie zbeam_test_cookie -eval \
  "N=list_to_atom(\"$name@127.0.0.1\"),
   true=net_kernel:connect_node(N),
   Call=fun(To,Cmd)->R=make_ref(),To!{self(),R,Cmd},
     receive {R,V}->V after 5000->error({workers_timeout,Cmd}) end end,
   Endpoint={zbeam_workers,N},
   {ok,A}=Call(Endpoint,{discover,a}),{ok,B}=Call(Endpoint,{discover,b}),
   N=node(A),N=node(B),true=(A=/=B),
   {error,noproc}=Call(Endpoint,{discover,unknown}),
   lists:foreach(fun(P)->lists:foreach(fun(Data)->
     D=crypto:hash(sha256,Data),{ok,D}=Call(P,{hash,Data}) end,
     [<<>>,<<97,98,99>>,binary:copy(<<90>>,1048576)]) end,[A,B]),
   {error,bad_request}=Call(A,{hash,42}),
   <<131,88,119,L,NB:L/binary,ID:32,S:32,C:32>>=term_to_binary(A,[{minor_version,2}]),
   Old=binary_to_term(<<131,88,119,L,NB/binary,(ID bxor 1):32,S:32,C:32>>),
   Stale=make_ref(),Old!{self(),Stale,{hash,<<1>>}},
   {ok,A}=Call(Endpoint,{discover,a}),
   receive {Stale,_}->error(stale_reply) after 0->ok end,
   Lost=erlang:monitor(process,A),LostName=erlang:monitor(process,Endpoint),
   true=monitor_node(N,true),true=erlang:disconnect_node(N),
   receive {nodedown,N}->ok after 5000->error(no_disconnect) end,
   receive {'DOWN',Lost,process,A,noconnection}->ok after 5000->error(no_pid_disconnect) end,
   receive {'DOWN',LostName,process,Endpoint,noconnection}->ok after 5000->error(no_name_disconnect) end,
   true=net_kernel:connect_node(N),{ok,A}=Call(Endpoint,{discover,a}),{ok,B}=Call(Endpoint,{discover,b}),
   Cancelled=erlang:monitor(process,A),true=erlang:demonitor(Cancelled,[flush]),
   Named=erlang:monitor(process,Endpoint),MA=erlang:monitor(process,A),MB=erlang:monitor(process,B),
   ok=Call(A,stop),receive {'DOWN',MA,process,A,normal}->ok after 5000->error(no_a_down) end,
   {error,noproc}=Call(Endpoint,{discover,a}),{ok,B}=Call(Endpoint,{discover,b}),
   D2=crypto:hash(sha256,<<1,2,3>>),{ok,D2}=Call(B,{hash,<<1,2,3>>}),
   receive {'DOWN',Cancelled,_,_,_}->error(cancelled_down);{'DOWN',MB,_,_,_}->error(sibling_down);{'DOWN',Named,_,_,_}->error(name_down) after 0->ok end,
   Dead=erlang:monitor(process,A),receive {'DOWN',Dead,process,A,noproc}->ok after 5000->error(no_dead_down) end,
   ok=Call(B,stop),receive {'DOWN',MB,process,B,normal}->ok after 5000->error(no_b_down) end,
   {error,noproc}=Call(Endpoint,{discover,b}),true=erlang:demonitor(Named,[flush]),
   true=lists:member(N,nodes()),
   io:format(\"PASS two-worker discovery hash reconnect independent-stop pid-name-monitor stale-route~n\"),halt()."
kill -0 "$pid"
echo "PASS $label two-worker profile"
