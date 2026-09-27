# Standard Allocator Baselines — Experimental Branch

- Date: 2026-09-27.
- Branch: `explore/allocator-baselines`, based on `11c3319`.
- Environment: Zig 0.16.0, Linux x86-64/WSL2, four visible CPUs; OTP 28/Elixir 1.19.5 for benchmarks, two BEAM schedulers.
- Scope: application-side allocator selection and isolated/loopback experiments. Default remains `process`; no battery dependency or ownership contract changed.
- Raw artifacts: [manifest](2026-09-27-allocators/baselines/manifest.json), [commands/results](2026-09-27-allocators/baselines/runs.jsonl), [lab summary](2026-09-27-allocators/baselines/lab-summary.tsv), [network summary](2026-09-27-allocators/baselines/network-summary.tsv), [individual samples](2026-09-27-allocators/baselines/samples.tsv.gz), [completion marker](2026-09-27-allocators/baselines/COMPLETE).

## Method and checks

The branch adds opt-in `-Dallocator=process|debug|smp|libc` and a libc-linkage control. The selected allocator is passed to the existing runtime; startup/I/O still use `process.Init`. Port payload storage remains fixed. No default was changed.

Workloads, counts and caveats are specified in `benchmarks/memory/README.md` on this branch. Five variants × three payloads × three workloads × five repetitions produced **225 successful process runs**. Lab runs contain three correlated cycles; each table value below is the median of five independent-launch medians. Network values are medians of five launches. **1,050,000 individual samples** reproduce all recorded percentiles; cycles are not counted as independent replications.

All runs were sequential and seed-shuffled. A run does not include compilation. The matrix asserts exact replies and rejects invalid payload sizes before starting the workload. End-to-end measurements use real loopback OTP; isolated echo timings exclude sockets and handshake.

Executed verification:

```sh
zig build test-all test-allocators -j2 --summary all
zig build test-all test-allocators -j2 -Doptimize=ReleaseSafe --summary all
zig build test-interop-docker -j2 -Doptimize=ReleaseSafe -Dallocator=smp --summary all
```

Debug and ReleaseSafe: **52/52 tests plus CLI regression passed**. Each of the five ReleaseSafe allocator variants passed **5/5 allocator checks**. SMP passed real OTP **25/26/27 in both handshake roles**, including rejection/reconnect/process-loss cases. Raw logs: [Debug](2026-09-27-allocators/verification/baseline-debug.log), [ReleaseSafe](2026-09-27-allocators/verification/baseline-release-safe.log), [SMP OTP](2026-09-27-allocators/verification/baseline-smp-otp.log). These logs retain expected peer-rejection diagnostics; commands exited zero.

A first combined variant-build command hit the 360-second tool limit; the remaining builds were rerun successfully before measurement. The initial RSS reader incorrectly treated procfs's reported zero length as EOF. A real-procfs regression reproduced it; streaming reads with fixed scratch storage corrected it before these samples were collected.

## Results

### Real distribution round trips

| Application allocator / linkage | 32 B p50 | 4 KiB p50 | 64 KiB p50 | 32 B round trips/s | 32 B child RSS |
|---|---:|---:|---:|---:|---:|
| process / no libc (existing default) | 619.354 µs | 665.389 µs | 1798.890 µs | 1572.3 | 1432 KiB |
| SMP / no libc | 529.329 µs | 493.456 µs | 1702.085 µs | 1844.3 | 1080 KiB |
| explicit DebugAllocator / libc | 708.594 µs | 743.875 µs | 1767.652 µs | 1366.6 | 2260 KiB |
| SMP / libc | 538.954 µs | 531.093 µs | 1684.005 µs | 1802.6 | 2152 KiB |
| libc allocator / libc | 529.230 µs | 487.370 µs | 1484.576 µs | 1855.0 | 2108 KiB |

The accompanying Port path remains faster: roughly 95–98 µs p50 at 32 B and 401–413 µs at 64 KiB across these launches. Allocator selection does not erase the distribution/Port gap.

### Isolated synchronous echo

| Application allocator / linkage | 32 B p50 | 64 KiB p50 | Allocations per 32 B echo |
|---|---:|---:|---:|
| process / no libc | 102.120 µs | 532.267 µs | 9 |
| SMP / no libc | 1.124 µs | 453.633 µs | 9 |
| explicit DebugAllocator / libc | 214.833 µs | 608.988 µs | 9 |
| SMP / libc | 1.188 µs | 447.540 µs | 9 |
| libc allocator / libc | 0.967 µs | 149.784 µs | 7 |

The libc path used successful resize/remap operations and fewer allocate/free fallbacks in this workload. The wrapper establishes allocation counts, not a complete CPU/copy/syscall explanation. The isolated and network measurements must not be conflated: a much faster codec loop does not imply an equally large service speedup.

The 128-slot remote handoff experiment passed data/ownership checks, but queueing and payload validation materially affect its latencies. It is not a nanosecond-level allocator-only comparison. Full handoff/RSS results are preserved rather than reduced to one headline score.

## Interpretation and next experiment

- **SMP/no-libc is the simplest candidate** for improving the current service without adding an external allocator or libc requirement. It is still opt-in on the branch.
- **libc is an important control**, especially for larger-buffer growth. It adds process/linkage overhead and is not a free replacement for the existing no-libc build.
- **Diagnostic and linkage configuration matter.** Comparing snmalloc only to the current diagnostic baseline would overstate evidence for an external dependency.
- **Transport/runtime scheduling needs separate diagnosis.** Sub-microsecond/microsecond allocation/codec results do not explain the remaining hundreds of microseconds on the wire.
- Next: compare pinned snmalloc and hardening against freshly run, matched libc-linked SMP/libc controls. A request-arena branch can separately test reducing backing allocations without a third-party dependency.

No native-host replication, CPU/syscall profile, useful native job, confidence-bound guarantee, multi-peer runtime, long soak or production-safety conclusion is established here.

## Reproduction

Build `zbeam`, `zbeam-port-echo` and `zbeam-allocator-bench` into five separate prefixes using `zig build` and `zig build build-allocator-bench`. For each prefix, set the allocator/linkage matching its label, then run:

```sh
python3 scripts/bench/allocator_matrix.py /tmp/allocator-results \
  process-nolibc=/tmp/zbeam-explore/process-nolibc \
  smp-nolibc=/tmp/zbeam-explore/smp-nolibc \
  debug-libc=/tmp/zbeam-explore/debug-libc \
  smp-libc=/tmp/zbeam-explore/smp-libc \
  libc=/tmp/zbeam-explore/libc
```

`manifest.json` records source and executable hashes. Evidence and this record are committed together; source hashes identify the measured working-tree version rather than treating the base commit as the complete experiment.
