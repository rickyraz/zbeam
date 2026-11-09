# Benchmarks

Benchmarks are evidence tooling, not product claims. Results record environment, optimization mode, payload, iteration count and raw output. Allocator comparisons must additionally identify the explicit backend, libc/linkage, I/O backend and allocator-specific flags.

## Bounded owner pressure observation

`benchmarks/owner_pressure.exs` self-checks 80 callers against a paused owned child and records instantaneous BEAM, owner, distribution-port and Linux `/proc` measurements before and after resume. See the [WSL2 observation](../docs/evidence/phase-c/2026-11-05-owner-pressure-observation.md) for commands, results and sampling limitations. This is not a native-host soak or an RSS bound.

## Owner soak

`benchmarks/owner_soak.exs EXECUTABLE sha256|custom SECONDS CALLERS` runs
concurrent callers per actor through one supervised `TwoWorkerOwner` for a fixed
time. Every result is checked exactly, `busy` is counted, and any other result,
or an owner restart, fails the run. Payload sizes are drawn from fixed lists up to
1 MiB (SHA-256) or 64 KiB (custom). A sampler records first/min/max/last native
and BEAM `VmRSS`, native `VmHWM`, BEAM total memory and owner queue length once a
second; latency percentiles use one successful call in eight. The manual
[Soak workflow](../.github/workflows/soak.yml) runs both profiles on an
ubuntu-24.04 GitHub runner.

```sh
elixir --erl '+S 2:2' --name soak@127.0.0.1 --cookie zbeam_soak_cookie \
  benchmarks/owner_soak.exs ./zig-out/bin/zbeam-custom-worker custom 60 2
```

Results describe one host and one run; they are not RSS, latency or fairness bounds.
See the [soak record](../docs/evidence/phase-c/2026-11-09-owner-soak.md).

## Allocator research

The [snmalloc evaluation plan](../docs/snmalloc-evaluation.md) defines a future isolated experiment; no snmalloc build target or result exists yet. The [source audit](../docs/evidence/phase-a/2026-09-26-allocator-source-audit.md) identifies `DebugAllocator` in the recorded no-libc ReleaseSafe executable. The Port payload path uses fixed storage, so the Port comparison alone cannot identify an allocator bottleneck. Compare an explicit `smp_allocator` configuration before adding an external backend, and preserve the existing results rather than relabeling them.

## Fixed SHA-256 worker comparison

`ZBEAM_BENCH_JOB=sha256` selects the registered `sha256` worker and a Port child doing the same digest. `ZBEAM_BENCH_PAYLOAD_BYTES` selects 1–1048576 bytes (default 32). Digests are verified exactly on both paths; the expected BEAM digest is computed before timing. The original echo/default output and raw 2026-09-26 baseline remain untouched.

```sh
ZBEAM_BENCH_JOB=sha256 ZBEAM_BENCH_PAYLOAD_BYTES=65536 ERL_FLAGS='+S 2:2' \
  zig build bench-port-vs-zbeam -Doptimize=safe -- 1000
```

[Repeated 32 B/64 KiB evidence](../docs/evidence/phase-c/2026-09-28-sha256-worker.md) reports the Port advantage; SHA-256 is not evidence of a general native speedup. A 32-byte reply versus a full-length echo changes output size, so these jobs must not be conflated.

## Port versus distribution

```sh
ERL_FLAGS='+S 2:2' zig build bench-port-vs-zbeam -Doptimize=safe -- 1000
```

Both paths use one BEAM process and one Zig worker, with the same 32-byte payload and sequential request/reply workload. The Port uses four-byte packet framing; distribution adds ETF/control framing and routing. Both paths warm up before measurement. EPMD and handshakes are outside steady-state latency samples.

| Field | Meaning |
|---|---|
| `p50_ns`, `p95_ns`, `p99_ns` | Nearest-rank percentiles of individual round trips |
| `roundtrips_per_second` | Iterations divided by measured batch wall time, including harness loop overhead |
| `child_rss_kib`, `child_hwm_kib` | Linux `/proc/PID/status` resident/high-water snapshots before child shutdown; `unavailable` elsewhere |
| `beam_total_bytes` | Whole BEAM memory snapshot after the workload, not memory attributable solely to this path |
| `restart_ns` | One orderly stop, relaunch and first successful reply; distribution readiness polling uses 5 ms intervals |
| `scheduler_busy_pct` | Sum of scheduler active-time deltas divided by total-time deltas; scheduler instrumentation is enabled for both paths |

Restart is one sample, not a percentile or crash-recovery SLO. Scheduler busy time includes runtime waiting and does not equal OS CPU utilization. The Port path runs first; no randomized ordering, loaded-system control, repeated confidence intervals or concurrent workload is implied.

Persist individual samples as well as summary output:

```sh
zig build -Doptimize=safe
ERL_FLAGS='+S 2:2' ZBEAM_BENCH_SAMPLES=/tmp/zbeam-samples.tsv \
  ./scripts/bench_port_vs_zbeam.sh 1000 > /tmp/zbeam-summary.tsv
```

The script validates exact replies and child exit status. Timeouts or mismatches fail the run. [September baseline evidence](../docs/evidence/phase-c/2026-09-26-mvp-runtime.md) includes raw results and limitations, including any Port advantage. This single-host workload is not a general performance or production-readiness claim.
