#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
zbeam_bin=${ZBEAM_BIN:-"$root/zig-out/bin/zbeam"}
smoke="$root/scripts/interop/otp_echo_smoke.sh"
ran_target=0
missing=0
for version in ${OTP_VERSIONS:-25 26 27}; do
    case "$version" in 25|26|27) ;; *) echo "unsupported target: $version" >&2; exit 1 ;; esac
    eval "erl_bin=\${OTP_ERL_$version:-}"
    if [ -n "$erl_bin" ]; then
        actual=$(timeout 15 "$erl_bin" +S 2:2 -noshell -eval 'io:format("~s",[erlang:system_info(otp_release)]),halt().')
        if [ "$actual" != "$version" ]; then
            echo "FAIL OTP_ERL_$version runs OTP $actual" >&2; exit 1
        fi
        "$smoke" "$erl_bin" "$zbeam_bin" "otp$version"
        ran_target=$((ran_target + 1))
    else
        echo "SKIP OTP $version: set OTP_ERL_$version to its erl executable"
        missing=$((missing + 1))
    fi
done
if [ "${ZBEAM_REQUIRE_ALL_OTP:-0}" = 1 ] && [ "$missing" -ne 0 ]; then
    echo "FAIL target matrix incomplete ($missing missing)" >&2; exit 1
fi
if [ "$ran_target" -eq 0 ]; then
    if ! command -v erl >/dev/null 2>&1; then echo "FAIL no Erlang executable" >&2; exit 1; fi
    "$smoke" "$(command -v erl)" "$zbeam_bin" development
    echo "NOTE development evidence only; no target-matrix pass"
else
    echo "Target entries passed: $ran_target; missing: $missing"
fi
