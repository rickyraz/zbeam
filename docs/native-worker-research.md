# Native Worker Performance Research

- **Status:** [baseline and batch matrix measured; experiment results](research-progress.md). A scoped preformed-batch result favors zbeam over ETF Port, not over direct NIF or raw Port. No candidate meets all promotion gates.
- **Date:** 2026-10-02.
- **Code baseline:** `38caeb4730712ef5b5a73eec6ceda999282917c1` (`feat/worker-lifecycle`).
- **Implementation inventory:** [implementation-status.md](implementation-status.md).
- **Release gates:** [development-plan.md](development-plan.md). This research does not relax them.

## Objective and comparison boundary

The performance objective is to find and reproduce useful workloads where zbeam outperforms both an ETF-over-Port worker and an appropriate direct Zigler NIF under equal resource budgets. Negative results remain valid outcomes. There is no claim that a separate TCP process can beat an in-process function on every small request.

Zigler generates **in-process NIFs**, marshalling BEAM terms through the NIF interface; that is not inherently an ETF serialization path. zbeam itself uses **ETF over Erlang Distribution**. A comparison must distinguish serialization, transport, scheduling and computation rather than label Zigler as an "ETF approach".

Isolation and recovery are independent advantages to measure, not substitutes for a performance win. External Ports already isolate native process failure too. Dirty or threaded NIFs change scheduling, not the OS-process crash boundary; ordinary returned NIF errors are not VM crashes.

Primary comparison references, reviewed 2026-10-02:

- [Zigler 0.16.0 NIF calling and term marshalling](https://hexdocs.pm/zigler/0.16.0/01-nifs.html).
- [Zigler 0.16.0 synchronous, dirty CPU and threaded strategies](https://hexdocs.pm/zigler/0.16.0/07-concurrency.html).
- [Erlang NIF lengthy-work guidance](https://www.erlang.org/doc/apps/erts/erl_nif.html#lengthy_work).

These documentation versions are comparison design inputs, not a claim that Zigler was installed or tested. Executed comparisons must pin dependency/source revisions and record the actual compiler compatibility.

## Branch map

All six branches start at the same shared planning commit above the code baseline. They are independent research starting points, initially local and unpushed; the common document avoids six copies of the benchmark contract. No experiment-specific implementation is included at initialization.

| Branch | Scope | First deliverable | Prerequisite for conclusions |
|---|---|---|---|
| `explore/zigler-baseline` | Direct NIF, raw Port, ETF Port and distribution comparison | Reproducible matched adapters, raw samples and a cost breakdown | Correct results and pinned environment |
| `explore/io-overhead` | Allocation, copying, socket and deadline-task overhead | Profile plus one measured, independently tested change | Shared comparison harness |
| `explore/beam-backpressure` | OTP sender saturation and heartbeat/demand interaction | Bounded slow-worker experiment with BEAM metrics | Real OTP and unchanged zero-read contract |
| `explore/worker-recovery` | External supervision and failure recovery | Repeated fault/restart example with explicit request outcomes | Test-owned child processes |
| `explore/batched-requests` | Correlated request/reply and bounded batching | Batch-size crossover curves against equally batched competitors | Shared harness and request-lifetime contract |
| `explore/actor-admission` | Two-worker progress, ownership and admission | Lifecycle ADR and bounded two-worker experiment | Pressure evidence and request correlation |

The baseline branch is the initial checkout. Subsequent experiment commits belong only to their named branch. Consumers of a completed harness must explicitly integrate its reviewed commit and record the resulting source hash; branch names alone do not identify measured code. Nothing is merged into `master` or pushed by this initialization.

Existing experiments remain separate controls, not completed work in these branches:

- `explore/allocator-baselines` at `27b0fee`: explicit standard allocator choices.
- `explore/request-arena` at `ff5ac17`: synchronous request-local arena; throughput/retained-memory trade-off, not zero-copy.
- `explore/snmalloc` at `62c511c`: optional adapter; the recorded decision does not promote it to the default.

The inherited [SHA-256 comparison](evidence/phase-c/2026-09-28-sha256-worker.md) favors Port in all four recorded echo/hash and payload-size comparisons. Measurements from different branches, timer configurations or hosts must not be combined into an apparent before/after improvement.

## Shared benchmark contract

### Competitors

| Label | Required path | Boundary |
|---|---|---|
| `zigler_sync` | Direct binary/term NIF arguments and results, without artificial ETF wrapping | In-process; only work reliably short enough for normal schedulers |
| `zigler_dirty_cpu` | Same computation on dirty CPU schedulers | In-process; required control for sustained CPU work |
| `zigler_threaded` | Same computation with Zigler's threaded option and bounded admission | In-process; report separately rather than substitute for a faster eligible mode |
| `port_raw` | Existing four-byte packet framing and raw binary worker | Separate process, no ETF |
| `port_etf` | Four-byte packet framing with ETF encode/decode on both sides | Separate process; a new comparator, not the existing Port benchmark |
| `zbeam_distribution` | Existing authenticated REG_SEND/SEND worker with finite I/O deadlines | Separate process, ETF and distribution framing |

BEAM `:crypto.hash/2` is an additional practical SHA-256 control, not proof of equal native implementations. The existing code implements only `port_raw` and `zbeam_distribution` comparisons. NIF and ETF-Port adapters are work for `explore/zigler-baseline`, not available commands yet.

### Workloads and fairness

1. Start with the existing echo and SHA-256 jobs at 32 B, 4 KiB, 64 KiB and 1 MiB. Echo exposes boundary cost; SHA-256 returns the same 32-byte digest on every path. Empty/malformed/oversized inputs belong in correctness checks, not successful-throughput totals.
2. Use the same computation, input bytes, output representation and validation on each native path. Record compiler, optimization, safety checks, CPU features, allocator and libc linkage. Prefer the same compiler where supported; otherwise label the compiler/library difference as a confound rather than silently weakening zbeam's Zig 0.16 requirement.
3. Record normal/dirty scheduler counts, worker counts, I/O backend and thread counts. Apply the same **total** CPU budget to BEAM plus native children. A process pool with extra cores must not compete against a one-worker NIF budget.
4. Measure sequential operation first. Bounded concurrent and batched cases are separate experiments; current one-peer servicing is not concurrent actor scheduling. Expose equivalent batch and in-flight limits to every comparator.
5. Include serialization, marshalling, queue wait, transfer and result construction in end-to-end samples. Only fixture creation and the expected-result oracle occur before timing. An encode-once/decode-never path is a separately labeled microbenchmark, not an ETF service comparison.
6. Measure unloaded BEAM and a fixed background BEAM workload separately. Include an unrelated process's response-latency probe. Normal synchronous NIFs must not be deliberately run past their safe work budget to manufacture a scheduling advantage; use dirty CPU or threaded controls for such work.
7. Pin Zigler and transitive dependencies in a benchmark-only project when implemented. No NIF dependency or external allocator is added to the production batteries. Toolchain failures and missing comparators are reported as unavailable, never as wins or successful runs.

### Measurement and win criteria

Before measuring a candidate, record its primary workload, comparator, metric, CPU/memory budget and sample counts. Pilot runs are not selection evidence. Use at least ten independent process launches per case with seeded paired/randomized path ordering and a declared warm-up. Choose enough per-launch samples for p99, preserve every latency and failure, and compute uncertainty across launches rather than treating correlated requests as independent repetitions.

Record p50/p95/p99 end-to-end latency, completed operations/s, bytes/s, CPU time, context switches, allocations/copies where measurable, BEAM scheduler activity, total process-tree peak RSS and post-idle RSS at declared intervals. NIF memory is inside BEAM; reporting only native-child RSS would make the memory comparison invalid. Allocator live bytes, retained capacity and OS RSS are distinct metrics. Profiled runs must be separate from uninstrumented score runs.

Any incorrect result, unexpected timeout, dropped reply, unbounded growth or correctness regression disqualifies a performance candidate. Fault-injection runs remain separate from steady-state scores and retain every expected and unexpected failure.

A scoped performance win requires one predeclared track:

- **Throughput:** at least 10% more completed operations/s, with request p99 no more than 5% worse.
- **Latency:** at least 10% lower request p99, with throughput no more than 5% worse.

For either track, total peak and post-idle RSS must stay within the declared absolute memory budget and no more than 10% above the comparator. Report run-level 95% confidence intervals for paired metric ratios; a noisy effect that cannot distinguish improvement from parity remains inconclusive. Repeat on native Linux outside WSL2 in a second session before promotion. These are research gates, not observed results or release SLOs.

A claim of outperforming Zigler uses the best eligible direct NIF mode on that named workload. Beating only ETF-over-Port, the old zbeam baseline, or a deliberately unsuitable NIF mode does not satisfy that claim. Background-process responsiveness and crash recovery get separate results; neither can be relabeled as lower request latency. Publish losses and the workload envelope alongside any wins.

## Experiment scopes

### `explore/zigler-baseline`

Reuse `benchmarks/port_vs_zbeam.exs`, `benchmarks/port_echo.zig` and the fixed worker in `src/zbeam/runtime/sha256.zig`. Preserve the historical runner/results; put optional NIF dependencies under benchmark tooling. Add raw-sample output and exact known-vector checks to each new adapter before timing. Separate pure computation, codec-only and end-to-end runs; an isolated codec speedup is not a service speedup.

**Exit:** runnable adapters for all required paths or explicit unavailability, dependency lock/provenance, recomputable raw results and no unqualified winner. Establish the baseline before optimizing it.

### `explore/io-overhead`

Profile `runtime.node.dispatch`, `transport.deadline.run`, distribution framing and ETF decoding/encoding. The current deadline wrapper races I/O and timer tasks per operation; that is a hypothesis to measure, not an established bottleneck. Start with CPU/syscall/context-switch and allocation/copy counts. Compare the existing explicit SMP allocator control before adding another allocator.

Apply one change at a time at the measured bottleneck. Finite deadlines, cancellation/join cleanup, wire bounds and no-prefetch admission remain enabled in candidate results. A timer-disabled run may diagnose overhead but is not an eligible production-speed comparison. Borrowing within one synchronous handler scope requires a documented lifetime and malformed/OOM regressions; it does not authorize escaped slices or a general zero-copy claim.

**Exit:** attributed profile, matched before/after measurements, and passing deadline, backpressure, ownership and OTP regressions. No io_uring, custom scheduler or `BufferHandle` implementation without separate evidence.

### `explore/beam-backpressure`

Extend `tests/stress/backpressure_stress.zig` with a real OTP sender and a test-only paused handler. Record OTP version, distribution busy limits, sender admission, `net_ticktime`, BEAM memory, observable distribution queues, sender progress and unrelated-process latency. Queue metrics that a target OTP cannot expose must be labeled unavailable.

Test pauses below, near and beyond the configured heartbeat window; distinguish expected backpressure from failed handler progress and disconnect. Test both resume and cancellation. Keep the sender/test duration bounded and all buffering visible. No speculative reads or invented credits may keep ticks alive at zero demand. If the invariant implies a maximum tolerable pause, publish that limit and an external failure policy rather than hiding it.

**Exit:** repeatable memory plateau or a documented failure, observable sender throttling, measured heartbeat boundary and clean reconnect. TCP-only evidence is insufficient for a BEAM-sender claim.

### `explore/worker-recovery`

Extend `examples/sha256_worker.exs` with an external owner/supervisor, bounded restart/backoff and node monitoring. Resolve each in-flight request explicitly on worker loss; do not silently replay non-idempotent work. Test process loss, a test-only native panic, controlled allocation failure, a non-cooperative handler and EPMD registration loss as distinct cases. I/O cancellation cannot safely preempt arbitrary CPU code.

Faults must target only recorded test-owned child PIDs. Use disposable BEAM instances for NIF crash comparisons and a private EPMD/container for daemon-loss cases, never the developer's shared VM or daemon. Do not add remotely callable crash endpoints to the worker. For zbeam and external Port cases, confirm the unrelated BEAM process remains responsive, old connection state is discarded, and a new request succeeds after restart. For NIF faults, record whether the disposable VM survives or requires restart; do not assume all returned errors are fatal.

**Exit:** repeated failure-detection/restart/first-good-reply distributions, bounded resources and documented request outcomes. An orderly restart sample is not a crash-recovery percentile; node monitoring is not process-monitor support.

### `explore/batched-requests`

Define correlation, connection incarnation and late-reply handling before introducing multiple outstanding requests. Start with the existing integer/tuple/binary representation; add references/maps only for an actual consumer, with bounded codec and OTP conformance tests. Do not claim `gen_server:call` compatibility from a custom request envelope.

Compare batches of 1, 8 and 32 independent jobs with a 1 MiB aggregate input ceiling, explicit term/frame overhead bounds and a finite in-flight byte/message budget. Exclude combinations exceeding the ceiling explicitly. Each SHA-256 job retains its own digest; hashing a concatenation is not equivalent work. Give NIF and Port paths the same batch API and limits. Include batch-fill wait in application latency and report per-job throughput/latency, not just batch round trips.

**Exit:** crossover curves, exact results/order/correlation checks, late-reply and disconnect tests, and no throughput obtained by moving unbounded queues into BEAM. Batching is a hypothesis for amortizing overhead, not an assumed advantage over equally batched NIFs.

### `explore/actor-admission`

Start with two useful workers, one fast and one deliberately slow, and compare a small external-process pool with shared-process actors at the same total resources. Before a task-owning runtime API, record an ADR for message ownership, allocator provenance, task joins, termination and mailbox storage lifetime. Reuse `std.Io` facilities and existing bounded mailboxes.

Define effective demand before reading a frame whose destination is not yet known. Summing mailbox credits cannot guarantee capacity for the next destination. Accept and measure bounded head-of-line blocking rather than introduce an unbounded pending-routing queue. Cover concurrent send/terminate/shutdown, stalled consumers, per-worker progress, count/byte limits and cancellation. Stable PID routing and any monitor/link controls require their own protocol evidence.

**Exit:** a reviewed lifecycle contract, adversarial two-worker tests, resource plateau and matched throughput/tail-latency results. No custom work-stealing scheduler or general supervision framework is required.

## Verification and promotion

Branch creation is not implementation evidence. Every behavior change includes a runnable regression in the same commit, preserves [ADR 0001](adr/0001-battery-pack-module-boundaries.md), and keeps ETF and actor independent with no transport-to-runtime/actor dependency.

Before promoting an experiment, run:

```sh
zig build
zig build test-unit
zig build test-integration
zig build test-conformance
zig build test-stress
zig build test-all -Doptimize=ReleaseSafe
zig build test-interop-docker -Doptimize=ReleaseSafe
```

Keep OTP 25/26/27 as explicit regression targets; benchmark OTP versions are recorded separately and do not silently widen support. Missing Docker/OTP/profiling tools are skipped evidence with a reason, never a pass. Preserve raw results, commands, environment, source/binary hashes and failure outcomes under `docs/evidence/phase-{a,b,c}` as appropriate. Update implementation status and the relevant lifecycle/specification sections only when behavior is actually implemented and verified.

A final decision is **promote**, **retain as experiment**, or **reject**, with the declared comparator/workload and regression budget. No default allocator, ownership strategy, protocol profile or scheduler changes merely because a branch exists.
