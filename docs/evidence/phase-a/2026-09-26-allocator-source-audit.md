# Allocator Source and Binary Audit

## Scope and environment

- Date: 2026-09-26.
- Project revision: `090bb60a183d43004b0816b6897abaf58d8eaeeb` (restricted MVP); accompanying changes are documentation only.
- Environment: Zig 0.16.0; Linux `6.6.114.1-microsoft-standard-WSL2`, x86-64.
- Requirement: preserve ADR 0001 and establish an interpretable allocator baseline before the [snmalloc experiment](../../snmalloc-evaluation.md).
- Expected result: identify the current application allocator, linkage and adapter contract, with upstream findings pinned to a source revision.
- Actual result: source selection identifies `DebugAllocator` for this no-libc ReleaseSafe build; both installed executables are static ELF binaries. snmalloc remains an unbuilt research candidate.

This is source/ABI and existing-binary inspection, not a snmalloc compatibility, performance or security result. No snmalloc adapter was compiled and no dependency was added to the project.

## Local allocation path

The inspected installed standard library is under `/home/rickyraz/.local/share/mise/installs/zig/0.16.0/lib/`.

| Evidence | Observation |
|---|---|
| `src/main.zig`, `main`/`run` | Receives `std.process.Init`; passes `init.gpa` into the runtime and transport clients |
| `build.zig`, executable root module | Uses the requested optimize mode; does not request libc linkage or replace the allocator |
| Installed `lib/std/start.zig:689–743` | Debug selects the debug allocator; non-Wasm ReleaseSafe selects it when libc is not linked; the alternate libc path selects `c_allocator`; another branch selects `smp_allocator` for applicable threaded builds |
| Installed `lib/std/mem/Allocator.zig:22–79` | Vtable requires `alloc`, `resize`, `remap`, `free` and `std.mem.Alignment`; the file also provides conservative `noResize`/`noRemap` implementations |
| `benchmarks/port_echo.zig` | Per-message payload is fixed storage, not a heap allocation; startup/I/O still use `process.Init` |
| `build.zig.zon` | Dependencies remain empty; there is no snmalloc build option or package |

The allocator-selection conclusion follows from the inspected source and build configuration. No allocation-entry-point tracing or cost attribution was performed. It must not be read as a measured explanation for the Port/distribution latency gap.

## Binary inspection

Executed:

```sh
zig build -j2 -Doptimize=ReleaseSafe --summary all
file zig-out/bin/zbeam zig-out/bin/zbeam-port-echo
readelf -d zig-out/bin/zbeam
readelf -l zig-out/bin/zbeam
sha256sum zig-out/bin/zbeam zig-out/bin/zbeam-port-echo
```

Build result: 5/5 steps succeeded, using cached compilation/install artifacts. Both executables were identified as x86-64, statically linked ELF files with debug information. `readelf` reported no dynamic section for `zbeam`, and there was no `PT_INTERP` entry. A malloc preload is therefore not a replacement for this binary's explicit Zig allocator.

Observed SHA-256 values identify the local artifacts; different paths/toolchain installations can change binary hashes without changing source behavior.

| File | SHA-256 |
|---|---|
| `zig-out/bin/zbeam` | `3c3d99c7da487e8cc6a3860b27001b14d3d177c4a53c8e605879e9b250e3d432` |
| `zig-out/bin/zbeam-port-echo` | `4be7a4dba8a43fd06fb76a0c7843e4aee576ebc1894c7e564843aad10cb1d0d3` |
| Zig `lib/std/start.zig` | `2839e5ca2d125604bff88adeadf463e6d42bdb37058bc02896cd9220cf27dc5b` |
| Zig `lib/std/mem/Allocator.zig` | `f6ad8a10185701ef1399350f127692ed5e89141773ea3c7e5ccc54a652120397` |

## Upstream inspection

The official GitHub latest-release URL resolved to `0.7.5` on the review date. A clean, shallow tag checkout resolved to:

```text
526c55bdffa17aae20a9a3d24fe68a7a3b8d9894
2026-06-17T04:51:46-06:00
grafted, HEAD, tag: 0.7.5
```

The timestamp is the commit timestamp, not a claimed release publication date. The temporary checkout was outside the project; it was not vendored. Reproduction:

```sh
research=$(mktemp -d)
git clone --depth 1 --branch 0.7.5 https://github.com/microsoft/snmalloc.git "$research"
test "$(git -C "$research" rev-parse HEAD)" = 526c55bdffa17aae20a9a3d24fe68a7a3b8d9894
git -C "$research" status --short
git -C "$research" show -s --format='%H%n%cI%n%D' HEAD
sha256sum "$research/CMakeLists.txt" \
  "$research/src/snmalloc/override/malloc.cc" \
  "$research/src/snmalloc/override/override.h" \
  "$research/src/snmalloc/global/threadalloc.h"
```

The source inspection covered the README, original research paper, 0.7 release notes, build/security documentation, CMake configuration, C ABI/prefix handling, allocation/alignment implementation, global C++ overrides, thread cleanup and license. Primary links and the implications are in [snmalloc-evaluation.md](../../snmalloc-evaluation.md#primary-sources).

| Pinned file | SHA-256 |
|---|---|
| `CMakeLists.txt` | `76be2133d968f48dfda9b8102910a1b311cb668cf5a204c1031480c2a1cfe716` |
| `src/snmalloc/override/malloc.cc` | `432f05b7112b6243e833b098257aba27847c70d667f2b1a0fc2974ccae8e3800` |
| `src/snmalloc/override/override.h` | `03b9021752109490533582585982cceb4cac045928b7cacf3997fed3437967af` |
| `src/snmalloc/global/threadalloc.h` | `8d0a311bac6aa8320a89614e4e7336836ab2959786c1d9b4edc2e7e992b3108f` |

Source observations: C++20 is the default with a C++17 fallback option; the C ABI can be prefixed; the static shim also packages global C++ allocation overrides; thread cleanup has platform-dependent choices. None proves that the proposed Zig integration links or tears down correctly.

## Existing-code verification

Executed again after the documentation work:

```sh
zig fmt --check build.zig src tests examples benchmarks
zig build test-all -j2 --summary all
zig build test-all -j2 -Doptimize=ReleaseSafe --summary all
```

Formatting passed. Debug and ReleaseSafe each passed 47/47 Zig tests and the CLI shell regression, with 27/27 build steps succeeding. Compilation was cached; test executions ran. Expected peer-rejection warnings (`InvalidDigest`, `PacketTooLarge`) produced Zig's misleading `failed command` diagnostic, but both commands exited zero with all tests passing.

The OTP matrix was not rerun for this documentation-only change; the existing [MVP matrix record](../phase-b/2026-09-26-mvp.md) remains the compatibility evidence. The [Port samples](../phase-c/2026-09-26-mvp-runtime.md) were not replaced or relabeled.

## Unverified work

- snmalloc compilation/linking and the Zig adapter.
- Allocation routing, OOM, alignment, resize, cross-thread free and TLS behavior in a snmalloc-enabled zbeam executable.
- Allocator profiling, comparative latency/throughput, retained memory, hardening or sanitizer results.
- Other targets or production readiness.

These are experiment gates, not completed work. The default allocator and battery dependency graph are unchanged.
