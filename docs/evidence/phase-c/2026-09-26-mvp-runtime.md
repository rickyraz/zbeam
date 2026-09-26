# Restricted MVP — Runtime, Backpressure and Baseline

## Revision and environment

- Date: 2026-09-26.
- Revision: working-tree implementation atop `ae6e75c0987904f4db8eef9bab97533e1783147f`; no release tag created.
- Contracts: ADR 0001; [MVP ownership/demand/lifecycle](../../mvp.md); [risk backlog](../../research-needed.md).
- Environment: [Phase B record](../phase-b/2026-09-26-mvp/environment.txt), Linux x86-64/WSL2, four visible logical CPUs, AMD Ryzen 5 5600H, Zig 0.16.0. Benchmark: ReleaseSafe binaries, OTP 28/ERTS 16.3, Elixir 1.19.5, two online BEAM schedulers.

## Runtime checks

```sh
zig build test-all -j2 --summary all
zig build test-all -j2 -Doptimize=ReleaseSafe --summary all
```

Both modes passed 47/47 Zig tests plus the CLI shell regression. Raw results are in the [Debug](../phase-b/2026-09-26-mvp/tests-debug.log) and [ReleaseSafe](../phase-b/2026-09-26-mvp/tests-release-safe.log) logs.

| Invariant | Executable check and result |
|---|---|
| Zero demand means no input work | Counted reader and failing allocator observe zero calls before `NoDemand`; one grant consumes exactly one frame and leaves the next untouched |
| Buffered prefetch cannot bypass credits | Demand-aware framing rejects a nonempty reader buffer without spending credit |
| Length/allocation bounds | Oversized frames rejected before allocation; partial header/body distinguished from clean EOF; nested arrays/copied bytes charged against one term budget |
| Per-connection cleanup | Oversized peer and bad-cookie connection close; later valid connections and clean EOF succeed |
| Logical single consumer | Different/zero token rejected; a copied token cannot overlap a blocked receive; guard clears after completion |
| Registry ownership | Duplicate names and live mailbox registrations rejected; names removed and queue closed on termination |
| MPSC ordering | Eight producers, 1,000 messages each, capacity 64: every producer sequence received exactly once in order |
| TCP pause/resume | One paused handler holds the only frame; sender cannot finish 1,024 × 64 KiB bodies during the pause; all frames complete after progress resumes |
| Cancellation cleanup | Canceling that paused handler joins the network tasks and releases the owned packet; testing allocator reports no leaks |

The socket stress test sends framed bytes through the real `runtime.node.dispatch` path with a test handler. It targets the post-authentication seam, not an OTP sender or an ETF decoder. The handler signals its pause; after 100 ms exactly one frame has reached it and the sender has not completed the 64 MiB workload. Resumption and task completion have bounded waits. This demonstrates TCP backpressure on this host, not BEAM distribution-queue behavior.

The dispatcher has no application prefetch queue, and each packet has one synchronous owner. Kernel socket buffers still exist. No assertion of zero-copy, TSAN cleanliness, or a fixed process RSS ceiling follows from these tests.

## Port comparison

```sh
zig build -Doptimize=ReleaseSafe -j2
ERL_FLAGS='+S 2:2' \
ZBEAM_BENCH_SAMPLES="$PWD/docs/evidence/phase-c/2026-09-26-mvp/latency-samples.tsv" \
  scripts/bench_port_vs_zbeam.sh 1000 \
  > docs/evidence/phase-c/2026-09-26-mvp/port-comparison.tsv
```

Workload: 100 warm-up round trips and 1,000 measured round trips, same 32-byte binary, one sequential BEAM sender. Initial startup/handshake is outside latency samples. Port runs before distribution. The child remains alive for memory sampling, then a final unmeasured exchange terminates the bounded distribution child.

| Metric | Erlang Port | zbeam distribution |
|---|---:|---:|
| p50 | 87.416 µs | 554.833 µs |
| p95 | 135.779 µs | 693.373 µs |
| p99 | 198.679 µs | 827.637 µs |
| Sequential round trips/second | 11,060.0 | 1,764.3 |
| Child RSS snapshot | 1,964 KiB | 1,468 KiB |
| Child high-water RSS | 1,964 KiB | 1,468 KiB |
| Whole BEAM memory snapshot | 55,592,320 bytes | 55,967,960 bytes |
| One stop/relaunch/first-reply sample | 4.715046 ms | 14.730439 ms |
| Scheduler active/total delta | 10.125% | 2.417% |

Raw [summary](2026-09-26-mvp/port-comparison.tsv) and [2,000 individual latency samples](2026-09-26-mvp/latency-samples.tsv) are preserved.

**Negative result:** the distribution path is slower than the Port path in every recorded latency percentile and in sequential throughput. Lower scheduler activity accompanies much lower throughput and is not evidence of better CPU efficiency. Lower child RSS in this one run is not a general memory advantage.

Restart includes orderly stop, relaunch, readiness checks and first reply. Distribution readiness polls at 5 ms intervals, so polling affects that sample. This is not externally supervised crash recovery or a restart percentile. Memory is sampled from `/proc`; BEAM memory includes the whole VM, not only one transport.

## Remaining limits

No confidence intervals, randomized benchmark ordering, concurrent workload, high-load BEAM scheduler test, allocator profile, additional payload-size matrix or sanitizer campaign was run. SIGKILL/nodedown evidence is recorded separately in [Phase B](../phase-b/2026-09-26-mvp.md). Actor-local panic isolation, transport deadlines and arena lifecycle remain unimplemented.
