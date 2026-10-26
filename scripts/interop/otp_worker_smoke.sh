#!/bin/sh
# Test-owned worker profile; the supplied erl may be a pinned Docker wrapper.
set -eu
erl_bin=${1:?ERL required}
bin=${2:?ZBEAM required}
label=${3:?LABEL required}
name="worker_${label}_$$"
log=$(mktemp)
pid=
cleanup() {
    status=$?
    [ "$status" -eq 0 ] || { printf '\nworker output:\n' >&2; cat "$log" >&2; }
    [ -z "$pid" ] || { kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; }
    rm -f "$log"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
sh "$(dirname "$0")/ensure_epmd.sh"
"$bin" serve-worker "$name" zbeam_test_cookie >"$log" 2>&1 &
pid=$!
tries=0
until grep -q '^registered ' "$log"; do
    kill -0 "$pid"
    tries=$((tries + 1)); [ "$tries" -lt 100 ] || exit 1
    sleep 0.1
done
timeout 35 "$erl_bin" +S 2:2 -noshell -name "wc_${label}_$$@127.0.0.1" -setcookie zbeam_test_cookie -eval \
  "N=list_to_atom(\"$name@127.0.0.1\"),
   true=net_kernel:connect_node(N),
   Call=fun(To,Cmd)->R=make_ref(),To!{self(),R,Cmd},
     receive {R,V}->V after 3000->error(worker_timeout) end end,
   {ok,P}=Call({zbeam_worker,N},discover),N=node(P),
   lists:foreach(fun(B)->D=crypto:hash(sha256,B),{ok,D}=Call(P,{hash,B}) end,
     [<<>>,<<97,98,99>>,binary:copy(<<90>>,1048576)]),
   {error,bad_request}=Call(P,{hash,42}),
   <<131,88,119,L,NB:L/binary,ID:32,S:32,C:32>>=term_to_binary(P,[{minor_version,2}]),
   Old=binary_to_term(<<131,88,119,L,NB/binary,(ID bxor 1):32,S:32,C:32>>),
   Stale=make_ref(),Old!{self(),Stale,{hash,<<1>>}},
   {ok,P}=Call({zbeam_worker,N},discover),
   receive {Stale,_}->error(stale_reply) after 0->ok end,
   Missing=erlang:monitor(process,Old),
   receive {'DOWN',Missing,process,Old,noproc}->ok after 3000->io:format(\"MONITOR MAILBOX ~p~n\",[process_info(self(),messages)]),error(no_noproc) end,
   Unknown=erlang:monitor(process,{zbeam_absent,N}),
   receive {'DOWN',Unknown,process,{zbeam_absent,N},noproc}->ok after 3000->error(no_named_noproc) end,
   LostName=erlang:monitor(process,{zbeam_worker,N}),
   Lost=erlang:monitor(process,P),
   {ok,P}=Call({zbeam_worker,N},discover),
   true=monitor_node(N,true),true=erlang:disconnect_node(N),
   receive {nodedown,N}->ok after 3000->error(no_disconnect) end,
   receive {'DOWN',Lost,process,P,noconnection}->ok after 3000->error(no_monitor_disconnect) end,
   receive {'DOWN',LostName,process,{zbeam_worker,N},noconnection}->ok after 3000->error(no_named_disconnect) end,
   true=net_kernel:connect_node(N),{ok,P}=Call({zbeam_worker,N},discover),
   Cancelled=erlang:monitor(process,P),true=erlang:demonitor(Cancelled,[flush]),
   Named=erlang:monitor(process,{zbeam_worker,N}),
   M=erlang:monitor(process,P),ok=Call(P,stop),
   receive {'DOWN',M,process,P,normal}->ok after 3000->error(no_normal_down) end,
   {error,noproc}=Call({zbeam_worker,N},discover),
   receive {'DOWN',M,_,_,_}->error(duplicate_down);{'DOWN',Cancelled,_,_,_}->error(cancelled_down);{'DOWN',Lost,_,_,_}->error(replayed_down);{'DOWN',Named,_,_,_}->error(discovery_died) after 0->ok end,
   true=erlang:demonitor(Named,[flush]),
   Dead=erlang:monitor(process,P),
   receive {'DOWN',Dead,process,P,noproc}->ok after 3000->error(no_dead_down) end,
   true=lists:member(N,nodes()),
   io:format(\"PASS worker identity hash stale-PID PID-and-name-monitor demonitor reconnect normal-stop node-survival~n\"),halt()."
kill -0 "$pid"
echo "PASS $label worker profile"
