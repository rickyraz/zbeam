# Request-Local Arena — Experimental Branch

- Reviewed: 2026-09-28; branch `explore/request-arena`, based on standard-allocator commit `27b0fee` (not on the separate snmalloc branch).
- Environment: Zig 0.16.0, Linux x86-64/WSL2, four visible CPUs; OTP 28/Elixir 1.19.5 benchmark VM with two schedulers.
- Decision: **retain as an opt-in branch experiment, not the default**. The 64 KiB workload improves, but isolated-echo RSS after 100 ms idle exceeds the 10% regression budget used for allocator promotion, and a useful worker workload/native-host replication is still missing.

## Implemented contract

`-Drequest-arena-retain=N` enables a `std.heap.ArenaAllocator` per authenticated synchronous connection in `runtime.node.dispatch`; omission preserves the existing allocator path. The CLI passes this build choice into `node.Config.request_arena_retained_bytes`. `N=0` releases backing storage after every frame; positive `N` bounds the arena's **retained logical capacity** between frames, not peak live bytes, physical allocator rounding or process RSS. No C++ object or other dependency is introduced. This is *not* the proposed transport `BufferHandle` arena or zero-copy transfer.

The frame, decoded control/payload, handler scratch and owned response use the request allocator. The handler only borrows the packet until `handle` returns; its response must use the supplied allocator. On success the reply is flushed before credit restoration; packet and response are released before reset on both success and error. No reference to the arena or its allocations may escape `handle` or survive the frame. One actor and one active peer make this a synchronous scope, not a general async task/message ownership strategy. EPMD, handshake, probe, process initialization and other application allocations retain their existing allocator domains. Frame/ETF limits and demand gating are unchanged.

A failed best-effort `retain_with_limit` resize can leave oversized backing storage. A reproduced fault-injection check initially failed with **12,326 bytes** retained despite a 512-byte cap ([before-fix failure](2026-09-27-allocators/verification/arena-reset-before-fix.log)); a `.free_all` fallback now enforces the cap even after that failure. This is a capacity/release regression test, not an OS-level memory-pressure campaign. The arena is drained at connection exit on every path.

## Verification

- `zig build test-all test-allocators -j2 -Dallocator=smp -Drequest-arena-retain=1048576 --summary all` — **55/55 tests**, CLI passed (Debug).
- Same command with `-Doptimize=ReleaseSafe` — **55/55 tests**, CLI passed.
- Same Debug command without experimental options — **55/55 tests**, CLI passed; the default remains `process` and arena disabled.
- `zig build test-interop-docker -j2 -Doptimize=ReleaseSafe -Dallocator=smp -Drequest-arena-retain=N --summary all` for **both `N=0` and `N=1048576`** — real OTP **25/26/27**, both handshake roles and rejection/reconnect/isolation scenarios passed.
- Allocation-failure iteration, warm reuse, zero-retention, deliberate reset resize/allocation failure, repeated request/connection behavior, TCP sender pause/resume and cancellation cleanup passed. The selected allocator's accounting reaches zero after queued tasks are joined.

Logs: [Debug](2026-09-27-allocators/verification/arena-debug.log), [ReleaseSafe](2026-09-27-allocators/verification/arena-release-safe.log), [default](2026-09-27-allocators/verification/arena-default.log), [zero-retention OTP](2026-09-27-allocators/verification/arena-zero-otp.log), [1 MiB-retention OTP](2026-09-27-allocators/verification/arena-1m-otp.log). Expected peer-rejection warnings are not test failures.

## Matched results

All variants select explicit SMP without libc or third-party linkage. A seeded, serial, five-launch matrix used 32 B, 4 KiB and 64 KiB payloads; each launch has three correlated cycles of 2,000 isolated operations or 1,000 real OTP round trips for both Port and distribution. **135 successful process runs; 630,000 raw latency samples** reproduce every reported percentile. Values below are medians of independent-launch medians for isolated echo, or medians of five network launches. The handoff workload is intentionally unchanged by the arena switch; its variability is a negative control, not an arena gain/regression claim.

| Variant | Isolated echo 32 B p50 | Isolated echo 64 KiB p50 | Isolated 64 KiB RSS after 100 ms idle | Network 32 B p50 | Network 64 KiB p50 | Network 64 KiB round trips/s | Network 64 KiB child RSS after work |
|---|---:|---:|---:|---:|---:|---:|---:|
| Disabled | 1.157 µs | 465.186 µs | 1300 KiB | 472.307 µs | 1599.995 µs | 614.9 | 1076 KiB |
| Reset/free all (0) | 1.073 µs | 389.878 µs | 1284 KiB | 459.888 µs | 1558.378 µs | 637.7 | 1068 KiB |
| Retain up to 1 MiB | 0.967 µs | 99.869 µs | 1480 KiB | 478.117 µs | 1094.515 µs | 894.1 | 1336 KiB |

At 64 KiB the retained variant's five network throughput runs range from **747.2 to 917.2 round trips/s**; the disabled runs range from **562.1 to 638.6**. The median throughput gain is approximately **45%**; the immediate post-work child-RSS rise from 1076 to 1336 KiB is approximately **24%**. Isolated echo's separately measured RSS after 100 ms idle rises from 1300 to 1480 KiB (**14%**). None of these differences is a confidence interval. Measured network peak child HWM at 64 KiB was 1336 KiB versus 1412 KiB disabled, so instantaneous, short-idle and peak measurements are distinct. At 32 B the network p50 is not improved by 1 MiB retention; the Port path remains substantially faster than distribution.

`profile_allocations` counts successful **backing** allocator requests in one untimed echo, not every arena sub-allocation. At 64 KiB the retained variant uses four backing allocations versus nine when disabled; its backing requested bytes are 789,940 versus 230,038. These counters are not physical RSS, copy counts or CPU attribution. The 1 MiB cap is retained capacity and does not replace the ETF or frame bounds.

Artifacts: [manifest and source/binary hashes](2026-09-27-allocators/arena/manifest.json), [commands/results](2026-09-27-allocators/arena/runs.jsonl), [lab summary](2026-09-27-allocators/arena/lab-summary.tsv), [network summary](2026-09-27-allocators/arena/network-summary.tsv), [raw samples](2026-09-27-allocators/arena/samples.tsv.gz), [completion](2026-09-27-allocators/arena/COMPLETE). The manifest's `base_commit` names the parent; its source/binary hashes identify the measured, not-yet-committed branch contents.

## Decision and next checks

The 1 MiB-retention option improves all five observed large-payload echo launches on this host. The isolated 64 KiB echo result also exceeds the **10% short-idle RSS budget** borrowed as a guardrail from the allocator evaluation. The network RSS sample is post-work, not an idle measurement. A smaller retention cap might change this trade-off but was **not measured**. Do not change the default, merge this into mainline as a general-purpose ownership solution, or assert that the arena is safe for detached handlers. Compare a useful worker job under its actual ownership contract, then repeat on native Linux outside WSL2 with CPU/copy/syscall attribution and longer idle/soak windows before any scoped opt-in deployment choice.

The separate snmalloc experiment is committed on `explore/snmalloc` (`62c511c`); it uses a namespaced external C++ object, matched libc controls and different raw runs. The branches should not be conflated into one performance claim. Deadline, heartbeat-versus-demand and EPMD-liveness work in [D1](../../development-plan.md#d1-constraints) remains higher priority.

## Reproduction

```sh
zig build -j2 -Doptimize=ReleaseSafe -Dallocator=smp -p /tmp/arena-off
zig build build-allocator-bench -j2 -Doptimize=ReleaseSafe -Dallocator=smp -p /tmp/arena-off
zig build -j2 -Doptimize=ReleaseSafe -Dallocator=smp -Drequest-arena-retain=0 -p /tmp/arena-zero
zig build build-allocator-bench -j2 -Doptimize=ReleaseSafe -Dallocator=smp -Drequest-arena-retain=0 -p /tmp/arena-zero
zig build -j2 -Doptimize=ReleaseSafe -Dallocator=smp -Drequest-arena-retain=1048576 -p /tmp/arena-1m
zig build build-allocator-bench -j2 -Doptimize=ReleaseSafe -Dallocator=smp -Drequest-arena-retain=1048576 -p /tmp/arena-1m
python3 scripts/bench/allocator_matrix.py /tmp/arena-results \
  arena-off=/tmp/arena-off arena-zero=/tmp/arena-zero arena-1m=/tmp/arena-1m
```

The output directory must not exist. Build and test each variant before measurement. Remaining gaps: no native-host repeat outside WSL2, CPU/syscall profiling, useful native job, concurrent peers, async message escape support, long soak or production security review.
