#!/bin/sh
set -eu
bin=${1:?usage: cli_smoke.sh ZBEAM}
logs=$(mktemp -d)
trap 'rm -rf "$logs"' EXIT
trap 'exit 130' INT TERM

# stdout inherits the shell's offset. A positional writer silently overwrites
# earlier output when a CLI is used in a redirected command group.
{ printf 'prefix\n'; "$bin"; printf 'suffix\n'; } >"$logs/output"
grep -q '^prefix$' "$logs/output"
grep -q '^Usage: zbeam echo ' "$logs/output"
grep -q '^       zbeam serve-sha256 ' "$logs/output"
grep -q '^suffix$' "$logs/output"

if "$bin" echo 'bad@name' cookie >"$logs/out" 2>"$logs/error"; then exit 1; fi
grep -q InvalidNodeName "$logs/error"
if "$bin" sha256 'bad@name' cookie >"$logs/out" 2>"$logs/error"; then exit 1; fi
grep -q InvalidNodeName "$logs/error"
if "$bin" unknown >"$logs/out" 2>"$logs/error"; then exit 1; fi
grep -q UnknownCommand "$logs/error"
echo 'PASS CLI streaming stdout and argument validation'
