# Benchmarks

Benchmarks are evidence tooling, not product claims. Results record environment, optimization mode, payload, iteration count and raw output.

## Port versus distribution

```sh
ERL_FLAGS='+S 2:2' zig build bench-port-vs-zbeam -Doptimize=ReleaseSafe -- 1000
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
zig build -Doptimize=ReleaseSafe
ERL_FLAGS='+S 2:2' ZBEAM_BENCH_SAMPLES=/tmp/zbeam-samples.tsv \
  ./scripts/bench_port_vs_zbeam.sh 1000 > /tmp/zbeam-summary.tsv
```

The script validates exact replies and child exit status. Timeouts or mismatches fail the run. [September baseline evidence](../docs/evidence/phase-c/2026-09-26-mvp-runtime.md) includes raw results and limitations, including any Port advantage. This single-host workload is not a general performance or production-readiness claim.
