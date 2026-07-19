#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
zbeam_bin=${ZBEAM_BIN:-"$root/zig-out/bin/zbeam"}
smoke="$root/scripts/interop/otp_echo_smoke.sh"
ran_target=0

for version in 25 26 27; do
    eval "erl_bin=\${OTP_ERL_$version:-}"
    if [ -n "$erl_bin" ]; then
        "$smoke" "$erl_bin" "$zbeam_bin" "otp$version"
        ran_target=1
    else
        echo "SKIP OTP $version: set OTP_ERL_$version to its erl executable"
    fi
done

if [ "$ran_target" -eq 0 ] && command -v erl >/dev/null 2>&1; then
    major=$(erl -noshell -eval 'io:format("~s",[erlang:system_info(otp_release)]),halt().' 2>/dev/null)
    "$smoke" "$(command -v erl)" "$zbeam_bin" "development_otp$major"
    echo "NOTE OTP $major is development evidence, not a target-matrix pass"
elif [ "$ran_target" -eq 0 ]; then
    echo "SKIP development smoke: erl unavailable"
fi
