#!/bin/sh
set -eu
bin=${1:?ZBEAM required}
custom_bin=${2:?CUSTOM_WORKER required}
logs=$(mktemp -d)
trap 'rm -rf "$logs"' EXIT
trap 'exit 130' INT TERM

# stdout inherits the shell's offset. A positional writer silently overwrites
# earlier output when a CLI is used in a redirected command group.
{ printf 'prefix\n'; "$bin"; printf 'suffix\n'; } >"$logs/output"
grep -q '^prefix$' "$logs/output"
grep -q '^Usage: zbeam echo ' "$logs/output"
grep -q '^       zbeam serve-sha256 ' "$logs/output"
grep -q '^       zbeam serve-worker ' "$logs/output"
grep -q '^       zbeam serve-workers ' "$logs/output"
grep -q 'ZBEAM_COOKIE' "$logs/output"
grep -q '^suffix$' "$logs/output"

if "$bin" echo 'bad@name' cookie >"$logs/out" 2>"$logs/error"; then exit 1; fi
grep -q InvalidNodeName "$logs/error"
if "$bin" sha256 'bad@name' cookie >"$logs/out" 2>"$logs/error"; then exit 1; fi
grep -q InvalidNodeName "$logs/error"
if "$bin" serve-worker 'bad@name' cookie >"$logs/out" 2>"$logs/error"; then exit 1; fi
grep -q InvalidNodeName "$logs/error"
if "$bin" serve-workers 'bad@name' cookie >"$logs/out" 2>"$logs/error"; then exit 1; fi
grep -q InvalidNodeName "$logs/error"
if "$bin" serve-workers valid cookie unexpected >"$logs/out" 2>"$logs/error"; then exit 1; fi
grep -q UnexpectedArgument "$logs/error"
if "$bin" unknown >"$logs/out" 2>"$logs/error"; then exit 1; fi
grep -q UnknownCommand "$logs/error"
if "$bin" serve-custom valid cookie >"$logs/out" 2>"$logs/error"; then exit 1; fi
grep -q UnknownCommand "$logs/error"
if "$custom_bin" serve-custom 'bad@name' cookie >"$logs/out" 2>"$logs/error"; then exit 1; fi
grep -q InvalidNodeName "$logs/error"
if "$custom_bin" serve-custom valid cookie unexpected >"$logs/out" 2>"$logs/error"; then exit 1; fi
grep -q UnexpectedArgument "$logs/error"
if env -u ZBEAM_COOKIE "$bin" serve-workers valid - >"$logs/out" 2>"$logs/error"; then exit 1; fi
grep -q MissingCookie "$logs/error"
if ZBEAM_COOKIE= "$bin" serve-workers valid - >"$logs/out" 2>"$logs/error"; then exit 1; fi
grep -q EmptyCookie "$logs/error"
echo 'PASS CLI streaming stdout and argument validation'
