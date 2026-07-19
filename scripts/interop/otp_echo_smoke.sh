#!/bin/sh
set -eu

erl_bin=${1:?usage: otp_echo_smoke.sh ERL ZBEAM LABEL}
zbeam_bin=${2:?usage: otp_echo_smoke.sh ERL ZBEAM LABEL}
label=${3:?usage: otp_echo_smoke.sh ERL ZBEAM LABEL}
short_name="zbeam_${label}_$$"
client_name="client_${label}_$$@127.0.0.1"
log=${TMPDIR:-/tmp}/"${short_name}.log"
peer_pid=
cleanup() {
    [ -z "$peer_pid" ] || kill "$peer_pid" 2>/dev/null || true
    rm -f "$log"
}
trap cleanup EXIT INT TERM

otp_release=$("$erl_bin" -noshell -eval 'io:format("~s",[erlang:system_info(otp_release)]),halt().' 2>/dev/null)
echo "RUN $label with OTP $otp_release"
epmd -daemon
"$zbeam_bin" echo "$short_name" zbeam_test_cookie >"$log" 2>&1 &
peer_pid=$!
tries=0
until epmd -names 2>/dev/null | grep -q "name $short_name "; do
    tries=$((tries + 1))
    if [ "$tries" -ge 50 ]; then
        echo "FAIL $label: zbeam did not register with EPMD" >&2
        cat "$log" >&2
        exit 1
    fi
    sleep 0.1
done

output=$("$erl_bin" -noshell -name "$client_name" -setcookie zbeam_test_cookie -eval \
    "N=list_to_atom(\"$short_name@127.0.0.1\"),
     io:format(\"connect=~p~n\",[net_kernel:connect_node(N)]),
     {echo,N}!{self(),hello},
     receive M -> io:format(\"reply=~p~n\",[M]) after 3000 -> halt(2) end,
     halt().")
wait "$peer_pid"
peer_pid=
printf '%s\n' "$output"
printf '%s' "$output" | grep -q 'connect=true'
printf '%s' "$output" | grep -q 'reply=.*hello'
echo "PASS $label"
