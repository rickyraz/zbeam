#!/bin/sh
# Build-graph regression: both runnable steps must forward arguments after --.
set -eu
zig=${1:-zig}
root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$root"
logs=$(mktemp -d)
trap 'rm -rf "$logs"' EXIT
trap 'exit 130' INT TERM
if "$zig" build run -- unknown >"$logs/run" 2>&1; then
    echo 'FAIL run arguments were not forwarded' >&2
    exit 1
fi
grep -q UnknownCommand "$logs/run"
# Isolate benchmark forwarding from Elixir availability and any EPMD daemon.
mkdir "$logs/bin"
printf '#!/bin/sh\nexit 0\n' >"$logs/bin/epmd"
printf '#!/bin/sh\nfor last; do :; done\n[ "$last" = args-smoke-marker ] || exit 1\nprintf "PASS benchmark argument forwarding\\n"\n' >"$logs/bin/elixir"
chmod +x "$logs/bin/epmd" "$logs/bin/elixir"
PATH="$logs/bin:$PATH" "$zig" build bench-port-vs-zbeam -- args-smoke-marker >"$logs/bench" 2>&1
grep -q 'PASS benchmark argument forwarding' "$logs/bench"
echo 'PASS build run and benchmark argument forwarding'
