#!/bin/sh
# Builds tests/package against an archive of this checkout fetched as a Zig
# package, so build.zig.zon `paths` must cover everything a consumer compiles.
set -eu
zig=${1:?ZIG required}
root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
trap 'exit 130' INT TERM
# Tracked and untracked-unignored files that exist, so local edits are included.
git -C "$root" ls-files -z --cached --others --exclude-standard |
    (cd "$root" && xargs -0 sh -c 'for f; do [ -f "$f" ] && printf "%s\0" "$f"; done; :' sh) |
    tar -C "$root" --null -T - --transform 's,^,zbeam/,' -czf "$work/zbeam.tar.gz"
cp -R "$root/tests/package" "$work/consumer"
cd "$work/consumer"
export ZIG_GLOBAL_CACHE_DIR="$work/global-cache"
"$zig" fetch --save=zbeam "file://$work/zbeam.tar.gz"
# The fetched package must contain only the declared paths.
tar -tzf "$ZIG_GLOBAL_CACHE_DIR"/p/zbeam-*.tar.gz | cut -d/ -f2 | sort -u >"$work/top"
printf '%s\n' LICENSE README.md build.zig build.zig.zon src | cmp - "$work/top"
"$zig" build run 2>"$work/run.log" || { cat "$work/run.log" >&2; exit 1; }
cat "$work/run.log"
grep -q '^PASS package consumer: .* SHA-256 ba7816bf$' "$work/run.log"
