#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
iterations=${1:-1000}
if ! command -v elixir >/dev/null 2>&1; then
    echo "SKIP Port baseline: elixir unavailable"
    exit 0
fi
epmd -daemon
exec elixir --name "zbeam_benchmark_$$@127.0.0.1" --cookie zbeam_bench_cookie \
    "$root/benchmarks/port_vs_zbeam.exs" \
    "$root/zig-out/bin/zbeam" "$root/zig-out/bin/zbeam-port-echo" "$iterations"
