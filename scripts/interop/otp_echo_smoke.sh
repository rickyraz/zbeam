#!/bin/sh
set -eu

erl_bin=${1:?usage: otp_echo_smoke.sh ERL ZBEAM LABEL}
zbeam_bin=${2:?usage: otp_echo_smoke.sh ERL ZBEAM LABEL}
label=${3:?usage: otp_echo_smoke.sh ERL ZBEAM LABEL}
short_name="zbeam_${label}_$$"
client_name="client_${label}_$$@127.0.0.1"
logs=$(mktemp -d)
peer_pid=
otp_pid=
client_pid=
hash_pid=
cleanup() {
    status=$?
    if [ "$status" -ne 0 ]; then
        for log in "$logs"/*; do [ ! -f "$log" ] || { printf '\n%s\n' "$log"; cat "$log"; }; done >&2
    fi
    [ -z "$peer_pid" ] || { kill "$peer_pid" 2>/dev/null || true; wait "$peer_pid" 2>/dev/null || true; }
    [ -z "$otp_pid" ] || { kill "$otp_pid" 2>/dev/null || true; wait "$otp_pid" 2>/dev/null || true; }
    [ -z "$client_pid" ] || { kill "$client_pid" 2>/dev/null || true; wait "$client_pid" 2>/dev/null || true; }
    [ -z "$hash_pid" ] || { kill "$hash_pid" 2>/dev/null || true; wait "$hash_pid" 2>/dev/null || true; }
    rm -rf "$logs"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

wait_registered() {
    tries=0
    until epmd -names 2>/dev/null | grep -q "name $1 "; do
        tries=$((tries + 1))
        if [ "$tries" -ge 100 ]; then echo "FAIL registration: $1" >&2; return 1; fi
        sleep 0.1
    done
}

otp_release=$(timeout 15 "$erl_bin" +S 2:2 -noshell -eval 'io:format("~s",[erlang:system_info(otp_release)]),halt().')
echo "RUN $label with OTP $otp_release"
epmd -daemon
"$zbeam_bin" serve "$short_name" zbeam_test_cookie >"$logs/zbeam.log" 2>&1 &
peer_pid=$!
wait_registered "$short_name"

# A rejected cookie must close only that connection, not the listening service.
timeout 15 "$erl_bin" +S 2:2 -noshell -name "bad_$client_name" -setcookie wrong_cookie -eval \
    "false=net_kernel:connect_node(list_to_atom(\"$short_name@127.0.0.1\")),halt()."
kill -0 "$peer_pid"

# Exact assertions, not output substring matching. SIGKILL is confined to the
# child created above; this is process-loss evidence, not a panic-safety proof.
timeout 40 "$erl_bin" +S 2:2 -noshell -name "$client_name" -setcookie zbeam_test_cookie -kernel net_ticktime 4 -eval \
    "N=list_to_atom(\"$short_name@127.0.0.1\"),
     Connect=fun() -> true=net_kernel:connect_node(N),true=monitor_node(N,true) end,
     Down=fun() -> receive {nodedown,N} -> ok after 3000 -> error(no_nodedown) end end,
     Echo=fun(M) -> {echo,N}!M, receive M -> ok after 3000 -> error(echo_timeout) end end,
     Connect(),
     lists:foreach(Echo,[hello,-2147483648,2147483647,{},[],[1,2,300],{self(),hello},binary:copy(<<90>>,65536)]),
     {absent,N}!ignored,Echo(after_unknown_route),
     timer:sleep(5000),Echo(after_idle_ticks),
     true=erlang:disconnect_node(N),Down(),Connect(),Echo(after_reconnect),
     {echo,N}!#{unsupported=>map},Down(),Connect(),Echo(after_bad_payload),
     Before=os:getpid(),
     Other=spawn(fun Loop() -> receive {P,ping} -> P!pong,Loop() end end),
     io:format(\"ISOLATION_READY~n\"),Down(),
     Before=os:getpid(),true=is_process_alive(Other),Other!{self(),ping},
     receive pong -> ok after 1000 -> error(sibling_stopped) end,
     io:format(\"PASS acceptor roundtrips idle-ticks cookie-rejection reconnect malformed-payload process-loss-isolation~n\"),halt()." >"$logs/client.log" 2>&1 &
client_pid=$!
tries=0
until grep -q '^ISOLATION_READY$' "$logs/client.log"; do
    kill -0 "$client_pid" 2>/dev/null || { wait "$client_pid"; exit 1; }
    tries=$((tries + 1)); [ "$tries" -lt 150 ] || exit 1; sleep 0.1
done
kill -KILL "$peer_pid"
wait "$client_pid"
client_pid=
cat "$logs/client.log"
wait "$peer_pid" 2>/dev/null || true
peer_pid=
# Registration lifetime must end with the child, not leak a stale EPMD entry.
tries=0
while epmd -names | grep -q "name $short_name "; do
    tries=$((tries + 1)); [ "$tries" -lt 50 ] || exit 1; sleep 0.1
done

# Reverse direction: real OTP accepts, zbeam discovers it through EPMD and
# initiates, sends a registered message, then validates its SEND reply.
otp_name="otp_echo_${label}_$$"
"$erl_bin" +S 2:2 -noshell -name "$otp_name@127.0.0.1" -setcookie zbeam_test_cookie -eval \
    'register(echo,spawn(fun Loop() -> receive {From,Value} -> From!{From,Value},Loop() end end)),
     io:format("ready~n"),receive stop -> halt() after 30000 -> halt(3) end.' >"$logs/otp.log" 2>&1 &
otp_pid=$!
wait_registered "$otp_name"
tries=0
until grep -q '^ready$' "$logs/otp.log"; do
    tries=$((tries + 1)); [ "$tries" -lt 100 ] || exit 1; sleep 0.1
done
timeout 15 "$zbeam_bin" probe "probe_${label}_$$" zbeam_test_cookie "$otp_name"
hash_name="sha_${short_name}"
"$zbeam_bin" serve-sha256 "$hash_name" zbeam_test_cookie >"$logs/sha256.log" 2>&1 &
hash_pid=$!
wait_registered "$hash_name"
timeout 25 "$erl_bin" +S 2:2 -noshell -name "sha_$client_name" -setcookie zbeam_test_cookie -eval \
    "N=list_to_atom(\"$hash_name@127.0.0.1\"),
     true=net_kernel:connect_node(N),
     lists:foreach(fun(B) -> D=crypto:hash(sha256,B),{sha256,N}!B,
       receive D -> ok after 3000 -> error(sha256_timeout) end end,
       [<<>>,<<97,98,99>>,binary:copy(<<90>>,65536)]),
     true=monitor_node(N,true),{sha256,N}!42,
     receive {nodedown,N} -> ok after 3000 -> error(expected_rejection) end,
     true=net_kernel:connect_node(N),
     D=crypto:hash(sha256,<<114,101,99,111,110,110,101,99,116>>),
     {sha256,N}!<<114,101,99,111,110,110,101,99,116>>,
     receive D -> ok after 3000 -> error(reconnect_timeout) end,
     halt()."
kill "$hash_pid"
wait "$hash_pid" 2>/dev/null || true
hash_pid=
echo "PASS $label OTP $otp_release: echo both roles; sha256 exact digest, rejection and reconnect"
