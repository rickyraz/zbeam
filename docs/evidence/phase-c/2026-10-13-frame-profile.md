# Encoder append candidate: allocation gain, no promotion

**Decision:** retain as a research candidate. Do not merge as a proven end-to-end performance win. No deadlines, demand checks or ownership guarantees were removed.

## Changes and checks

`etf.encodeInto` appends a standalone ETF term to a caller-owned array and restores its previous length on error. `encode` delegates to it; distribution encoding now appends control/payload into one array rather than allocating separate encoded terms and copying both. Capacity remains allocated after a failed append. Tests cover prefix preservation, allocation-failure cleanup and exact frame bytes. This is not zero-copy: output growth may relocate data, and decoding still owns its terms.

Zig 0.16.0 on four-CPU WSL2: `test-all test-research` passed **57/57 in Debug and ReleaseSafe**. The pinned Docker **OTP 25, 26 and 27** matrix passed. Optional profiling dependencies do not enter the battery DAG.

## Attribution

Ten serial fresh launches per allocator, with alternating legacy/candidate order, ran the same-binary encoder control. Each cell used 100 warmups and 1000 measured calls. The compact integer-control fixture isolates encoding; real REG_SEND/SEND tuples are covered by the separate network run. Median-of-launch p50 (microseconds):

| Allocator | Stage | 32 B | 4 KiB | 64 KiB |
|---|---|---:|---:|---:|
| process allocator | legacy | 32.918 | 48.993 | 175.579 |
| process allocator | append | 18.631 | 29.917 | 101.092 |
| SMP control | legacy | 0.241 | 2.866 | 145.597 |
| SMP control | append | 0.150 | 1.633 | 84.511 |

Instrumented allocation calls fell from five to two for these fixtures. No-op finite-deadline execution remained about 121.6 µs with the process allocator and 94.0 µs with SMP; no production allocator change follows. This is an attribution signal, not permission to remove cancellation/deadline safety. `perf`/`strace` attribution and syscall/context-switch counts were unavailable.

## End-to-end paired measurements

The committed fresh-VM comparison runner used the same existing adapter, schedulers and process allocator for both binaries. Eighty launches produced 80,000 exact-result samples: ten paired repetitions × two binaries × echo/SHA-256 × 32 B/64 KiB. Case order was seeded and shuffled within repetition. No builds or other experiments ran during these launches. Raw results include p50/p95/p99, CPU ticks, RSS observations and binary hashes.

| Job / input | Original p50 | Append p50 | Paired throughput ratio, 95% bootstrap interval |
|---|---:|---:|---:|
| echo / 32 B | 305.656 µs | 293.321 µs | 1.048 [1.021, 1.131] |
| echo / 64 KiB | 659.183 µs | 576.929 µs | 1.137 [1.098, 1.182] |
| SHA-256 / 32 B | 301.928 µs | 291.675 µs | 1.014 [0.996, 1.071] |
| SHA-256 / 64 KiB | 533.804 µs | 540.100 µs | 0.963 [0.936, 1.015] |

Ratios are candidate/original, calculated per paired launch before taking the median; intervals bootstrap those ten pairs, not individual requests. The 64 KiB echo improvement is promising but its lower throughput bound is below 10%. SHA-256 shows no established improvement, and its 64 KiB p99 ratio is 1.160 [0.946, 1.285], leaving meaningful tail-regression risk. Native Linux, loaded-BEAM and complete memory promotion gates remain unverified. This does not establish superiority over NIF or Port. Historical baseline latencies are not compared across dates as if they were paired.

## Reproduce

```sh
zig build test-all test-research build-frame-profile -j2 -Doptimize=ReleaseSafe
zig build test-interop-docker -j2 -Doptimize=ReleaseSafe
./zig-out/bin/zbeam-frame-profile process forward
./zig-out/bin/zbeam-frame-profile smp reverse
# ORIGINAL contains the unchanged baseline binary and built optional Zigler harness.
python3 scripts/bench/frame_compare.py "$ORIGINAL" /new/output/directory
```

Raw TSV/build/OTP logs and compressed network samples: `2026-10-13-frame-profile/`. Baseline source is `f463f73`; this branch contains the exact candidate and reproducer. Revert this one branch commit to remove the API/candidate without changing other research tracks.
