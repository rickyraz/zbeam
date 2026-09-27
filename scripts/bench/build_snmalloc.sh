#!/bin/sh
# Native Linux x86-64 lab artifact; never fetched or linked by the default build.
set -eu
src=${1:?usage: build_snmalloc.sh CHECKOUT OUTPUT.o [normal|checks]}
out=${2:?missing output object path}
mode=${3:-normal}
revision=526c55bdffa17aae20a9a3d24fe68a7a3b8d9894
[ "$(uname -s)" = Linux ] && [ "$(uname -m)" = x86_64 ] || { echo 'native Linux x86-64 required' >&2; exit 1; }
[ "$(git -C "$src" rev-parse HEAD)" = "$revision" ] || { echo 'wrong snmalloc revision' >&2; exit 1; }
[ -z "$(git -C "$src" status --porcelain)" ] || { echo 'snmalloc checkout must be clean' >&2; exit 1; }
set -- -std=c++20 -O3 -DNDEBUG -fno-exceptions -mcx16 \
  -DSNMALLOC_USE_WAIT_ON_ADDRESS=1 -DSNMALLOC_USE_PTHREAD_DESTRUCTORS \
  -DSNMALLOC_STATIC_LIBRARY_PREFIX=zbeam_sn_
case "$mode" in normal) ;; checks) set -- "$@" -DSNMALLOC_CHECK_CLIENT ;; *) echo 'unknown hardening mode' >&2; exit 1 ;; esac
mkdir -p "$(dirname "$out")"
zig c++ "$@" -I"$src/src" -c "$src/src/snmalloc/override/malloc.cc" -o "$out"
if nm -g --defined-only "$out" | grep -Eq ' (malloc|free|realloc|calloc|aligned_alloc|posix_memalign|_Zn[aw].*|_Zd[al].*)$'; then
  echo 'unexpected global allocation override' >&2
  exit 1
fi
{
  printf 'revision=%s\nhardening=%s\n' "$revision" "$mode"
  zig version
  zig c++ --version
  printf 'compiler_flag=%s\n' "$@"
  sha256sum "$out" "$src/src/snmalloc/override/malloc.cc"
  printf '\nUndefined symbols (no C++ runtime expected):\n'
  nm -u "$out"
} > "$out.txt"
printf 'Built %s (%s); namespaced C ABI, malloc.cc only\n' "$out" "$mode"
