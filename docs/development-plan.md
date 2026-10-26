# Development Plan: MVP to a Supported Native Worker Peer

- **Status:** W0–W5 implemented and verified on `feat/monitorable-worker`; broader D0–D5/M2 gates remain proposals.
- **Reviewed:** 2026-10-26.
- **Historical planning baseline:** local `master` at `11c3319`; restricted MVP introduced by `090bb60`. The compiler candidate includes live remote master's accepted labs at `497d346`.
- **Immediate milestone:** M1, one PID-addressable, monitorable native worker with external recovery.
- **Allocator track:** [snmalloc evaluation](snmalloc-evaluation.md).
- **Compiler track:** [Zig 0.17 migration](zig-0.17-migration.md) verified all 14 profiles; compiler PR #2 merged. [Consolidation executed](evidence/phase-a/2026-10-26-branch-consolidation.md): eleven local/remote branches retain M1 and all nine research topics, separately from feature acceptance.

## Direction

The product target is a Zig library and separate-process worker node that Erlang/Elixir applications can address, monitor and operate predictably. It is not a replacement BEAM VM, a NIF framework, or an attempt to implement every OTP service.

The differentiator must be useful native worker identities and lifecycle control through distribution, not an unsupported claim that distribution is faster than Ports. The recorded 0.16 32-byte benchmark favors Port and uses a diagnostic allocator in its no-libc ReleaseSafe configuration. Zig 0.17 startup selects SafeAllocator in debug/safe; old timings are not new-compiler evidence. Allocator and transport costs must remain separate.

The supported profile must state its actual ETF tags, control operations, platforms and OTP versions. A release cannot turn the v0.5 historical pseudocode into an implementation claim.

## Immediate target — M1: a monitorable native worker

M1 delivers a bounded native worker that a BEAM application can discover,
address by PID, monitor and recover through an external supervisor. It is a
subset of D1/D2/D5 below, not the production release or a general actor runtime.

The initial profile retains one active peer and one outstanding work request.
It uses the fixed SHA-256 workload, owned copies and explicit cleanup; no
tracing GC, arena or zero-copy mechanism is introduced. Monitor/control state
also needs explicit bounds; one work request does not bound monitor traffic.

### Acceptance scenario

1. A BEAM client obtains the native worker PID through a documented service
   exchange, without assuming `rpc:call`, `global` or `gen_server:call` support.
2. The client monitors that PID, sends bounded work and checks the exact digest.
3. A test-owned controlled worker exit removes its identity and produces the
   appropriate process-monitor notification while the native node remains alive.
4. Process loss, connection loss and a noncooperative handler are distinct tests;
   they do not masquerade as a controlled actor exit. BEAM remains responsive.
5. The external owner tears down/relaunches the worker process as needed. A fresh
   PID completes new work; stale PIDs and old replies cannot reach its replacement.
6. Uncertain requests fail explicitly. Recovery does not silently replay them.

The lifecycle ADR must define application-request errors separately from worker
exit. Native panic, corruption and noncooperative CPU work remain process-level
failure risks, not recoverable actor-local exceptions.

Links, native supervision trees, arbitrary actor spawning, preemptive scheduling,
concurrent peers and a general OTP compatibility claim are outside M1. The full
mandatory-capability/ETF gap must still be inventoried and any residual limits
published; adding monitors alone does not establish general node compatibility.

## M1 execution record — 2026-10-25

The W0–W5 development profile is implemented on the integration branch, not yet
merged into `master`. [Implementation status](implementation-status.md) and
[M1 evidence](evidence/phase-c/2026-10-25-m1.md) define the verified subset.
Debug/ReleaseSafe core tests and pinned OTP 25/26/27 pass; the Linux external
owner has separate Elixir 1.20.4/OTP 29 recovery evidence. Production release,
complete ETF capabilities and a task-owning actor scheduler are not complete.

W4 required a source-backed correction: OTP sends process monitors only when
both PID and named-monitor flags are present. Both target forms are implemented;
named discovery monitoring survives worker stop. The accepted lifecycle ADR
records that extension rather than redefining flag semantics (superseding
[ADR 0003](adr/0003-pid-and-named-monitor-capabilities.md)).

The historical pre-migration audit observed remote master `497d346` and stale
local `11c3319`; neither is the current integration base. Compiler PR #2 and its
evidence are on master `3919341`, now integrated into M1 by ordinary merge
`664fc81`. [Current merge-result verification](evidence/phase-b/2026-10-26-m1-acceptance.md)
passes locally in debug/safe, native OTP 25/26/27 and all complementary owner
cases. [PR checks, work-unit review and explicit size-exception approval](m1-review.md)
remain gates before M1-to-master integration. M2 has not started.

## Research inputs, not completed prerequisites

This table preserves the original local branch snapshot, not integration approval.
The later remote audit confirms lab-contracts is now merged into remote master;
the other inspected research tips are not promoted by this plan. Audit shared
ancestry before selecting changes; wholesale research merges can import unrelated
benchmarks.

| Branch / inspected tip | Reuse for this plan | Treatment |
|---|---|---|
| `explore/zigler-baseline` / `d0f9ff2` | Shared handshake/frame deadlines, EPMD fail-stop and SHA-256 foundations | Review common commits `7b812d3`, `c47968d`, `38caeb4` first; baseline benchmark work is not required |
| `explore/beam-backpressure` / `7f3e5fb` | Bounded OTP pause/heartbeat and test-owned fault probes | Reuse correctness evidence/harness; prolonged pause still permits disconnect |
| `explore/worker-recovery` / `e08175e` | External single-flight owner, timeout teardown and no-replay recovery | Adapt after identity/monitor semantics; it currently uses node/Port loss, not native process monitors |
| `explore/actor-admission` / `ddf5ece` | Joined-operation lifetime rules and conservative two-worker admission ADR | Design input now; multi-actor runtime remains M2 |
| `explore/lab-contracts` / `2fa1911` | Executable framing, identity and ownership counterexamples | Optional regression assets, not proof of full lifecycle safety |
| `explore/io-overhead` / `d6656b0` | Encoder allocation candidate | Defer; not a lifecycle dependency |
| `explore/batched-requests` / `8f161ea` | Bounded batch experiment | Defer; single-job worker is sufficient for M1 |

## Final deliverable

The first production-scoped release is complete only when all of the following exist:

1. A consumable Zig package preserving the five-battery DAG and a behavior-free umbrella; no mandatory third-party allocator for standalone ETF/actor consumers.
2. A small native worker service with named actors, PID-directed replies, documented process-monitor/link behavior and explicit error/termination semantics.
3. Bounded message ownership, queues and admission; slow workers propagate backpressure rather than growing hidden buffers.
4. Documented startup, timeout, reconnect/incarnation, shutdown and external supervision behavior. Cooperative errors remain controlled; a native panic may still end the native process, never a promise of actor-local panic isolation.
5. A declared and tested OTP/OS/architecture support matrix, security policy, operational diagnostics and reproducible failure tests.
6. A real Erlang/Elixir example issuing useful native work, handling worker loss and recovering under an external supervisor. Echo remains a protocol fixture, not the only product demonstration.
7. Repeated workload measurements and a published allocator decision: standard allocator by default unless an alternative meets the same correctness, memory and maintenance gates.
8. Package/archive consumption tests, versioned API documentation and a reviewed release checklist.

snmalloc is optional to this outcome. A successful evaluation may conclude that the standard allocator is sufficient. Neither io_uring nor zero-copy is a prerequisite.

## Execution sequence

Phases are evidence gates, not calendar promises. The M1 increments below take
priority over optional performance research. The allocator investigation can run
separately, but it cannot bypass reliability gates or justify speculative
scheduler changes. M1 deliberately precedes D3's general concurrent runtime.

| Phase | Work | Primary locations | Exit evidence |
|---|---|---|---|
| D0 — Make the baseline interpretable | Record actual allocator, libc linkage, optimizer and I/O backend. Profile allocation, copies, framing and system calls separately. Compare explicit standard allocators before an external dependency. | `benchmarks/`, `src/main.zig`, build options for experiments | Repeatable raw results with allocation routing proved; no change to the default based only on a microbenchmark |
| D1 — Reliable one-peer service | Bound handshake/read/write waits; preserve cancellation errors; define EPMD loss, handler progress diagnostics and shutdown. Keep positive-demand admission. | `transport/handshake_io.zig`, `distribution_io.zig`, `runtime/node.zig` | Silent/partial peer, blocked writer, cancellation and reconnect tests terminate within declared bounds; no leaks, stale demand or fabricated grants |
| D2 — Honest protocol surface | Close the mandatory-capability/ETF gap with bounded codecs; add PID addressing and required control operations incrementally. Define monitor/link reasons and node incarnation behavior. | `etf/`, `protocol/`, fixtures, OTP tests | Every supported flag/operation maps to code, malformed-input tests and target OTP evidence; unsupported profiles remain explicit |
| D3 — Small concurrent runtime | Connect caller-visible spawn/termination to supervised task lifetime. Add two or three useful actors only after ownership/admission rules are specified. | `actor/`, `runtime/`, stress tests | Race-safe send/terminate/shutdown; bounded slow-consumer behavior; stable PID lifetime; independent actor progress without unbounded per-peer queues |
| D4 — Measured allocator/ownership decision | Apply the isolated allocator results to representative service workloads; optionally promote snmalloc. Reduce avoidable allocations/copies only where profiles justify it. | `benchmarks/memory/`, optional application adapter, evidence | Repeated standard-versus-snmalloc results, equivalent build settings, unchanged safety gates and a written adopt/retain/reject decision |
| D5 — Supported release | Package and deployment checks, secret handling, supported transport security profile, supervision example, fuzz/soak/fault campaigns and release documentation. | package metadata, CI, examples, security docs | All final-deliverable gates pass on the declared targets; residual limits are documented and accepted |

### D1 constraints

- Deadlines cancel I/O; they do not safely preempt arbitrary CPU-bound Zig code. Handlers must cooperate with cancellation or the OS supervisor must terminate/restart the process.
- Demand pause and failed actor progress are different states. Diagnostics must identify both without inventing credits.
- Heartbeats share the connection. Resolve the pause/heartbeat policy explicitly; do not silently add speculative reads around the demand contract.
- EPMD registration loss must have an observable fail/stop/re-register policy, not leave a supposedly discoverable service running indefinitely.

### D2 constraints

- Implement data representations and wire validation; supporting an ETF function tag does not require executing Erlang functions.
- Required modern-OTP flags currently cover more encodings than the MVP decoder. Production-scoped support requires resolving this mismatch rather than advertising aspirational capabilities.
- Node-down monitoring already tested by the MVP is not process-monitor support.
- Atom caches/fragmentation remain disabled unless separately implemented with assembly count, byte and time limits. No broad protocol conformance claim follows from the send subset.

### D3 constraints

- `Runtime(T).spawn` currently registers storage; it is not a scheduler. Any task-owning API change requires a lifecycle ADR and migration notes.
- Queue elements need an explicit owning representation and allocator provenance. Removing a registry entry must not invalidate a mailbox still used by a resolved send.
- Multiple actor routes on one connection require a reviewed effective-demand/admission rule. Simply summing credits can read a message for a stalled destination. Accept bounded head-of-line blocking before inventing unbounded pending queues.
- Start with the existing `std.Io` task/group facilities and bounded queues. No custom work-stealing scheduler, general supervision tree or arena partitioning without a demonstrated requirement.

### D4 constraints

- snmalloc changes allocation behavior, not ETF encoding, task safety, network deadlines or zero-copy semantics.
- First compare against an explicit `std.heap.smp_allocator` configuration, not only against the current diagnostic allocator.
- Do not create extra actors or threads merely to produce a workload where snmalloc wins.
- Prefer owned copies and ordinary allocator injection. Arena, generation/handle APIs and shared-binary fan-out require separate evidence and are not bundled into the allocator change.

### D5 constraints

- Keep current OTP 25/26/27 tests as regression evidence; review upstream maintenance status when choosing deployment-supported OTP versions. Reevaluate the matrix rather than treating an old target list as a perpetual support promise.
- The library package must build from its exported archive, not only this checkout. Audit `build.zig.zon.paths` against all build-required assets and test a standalone battery consumer without benchmark/C++ dependencies.
- Do not expose the argv-cookie development interface as production secret management. Define a trusted-network/TLS policy, deployment boundary and incident-reporting process before widening the bind address.
- Production evidence requires native-host repetitions beyond WSL2, an explicit long-running soak and separate controlled-error, OOM, panic and process-loss scenarios.

## Active implementation increments

W0–W5 implementation is complete in the current development profile; M1
acceptance/integration remains gated separately. The increments below retain the
requirements and review boundaries, not an unexecuted-task inventory. Each
implementation increment includes its tests, contract updates and evidence in
the same reviewable work unit. Split codec, routing and monitor changes at independently verifiable
boundaries; do not bundle all research branches into one integration commit.

```text
W0 reviewed foundation -> W1 lifecycle ADR -> W2 bounded wire representations
                                         -> W3 single-worker identity/routing
(W2 + W3) -> W4 process monitors -> W5 external recovery -> M1 acceptance
M1 -> M2 bounded task-owning runtime -> later links/native supervision decisions
```

### W0 — Establish one reviewed reliability baseline

- Start from `master`; inventory shared research commits and selectively integrate
  handshake/frame/write budgets, EPMD fail-stop and the useful SHA-256 worker.
  Keep optional benchmark/fault executables outside runtime dependencies.
- Pin Zig 0.16.0 explicitly for this baseline. A Zig 0.17 migration is a separate
  verified build/API change, not bundled with lifecycle/protocol changes. Once
  adopted, use one recorded compiler revision for all subsequent evidence.
- Recheck bad cookie, partial handshake/frame, blocked writer, zero-demand
  read/allocation, cancellation and next-peer recovery. Import branch evidence
  only as historical evidence; run the integrated tree again.
- Define the supported bounded-handler/pause policy and observable shutdown.
  Do not keep heartbeats alive by reading without demand or adding hidden queues.

**Exit:** a reproducible baseline with Level A/B/C and OTP regression results;
remaining handler/heartbeat limitations are explicit. No performance win required.

### W1 — Accept a worker identity, ownership and termination ADR

- Define `starting -> running -> stopping -> stopped`, allowed transitions,
  request-error versus worker-exit reasons, and failure paths during startup.
- Assign one owner to worker state, mailbox contents, packet copies, names,
  monitor records and task storage. Stop admission, settle in-flight operations,
  release queued payloads and join tasks before freeing their storage.
- Specify node creation/incarnation and non-reused worker PID identity across
  worker/process restart, including finite-counter exhaustion. A TCP reconnect
  alone does not change the running worker's identity or restore old monitors.
- Define identity removal ordering, name reuse, PID discovery and request/reply
  correlation. Choose bounded reason terms and explicit connection-loss policy.
- Record the future multi-actor admission constraint without changing the
  caller-owned `Runtime(T).spawn` API into an implicit scheduler.

**Exit:** an accepted ADR and observable test matrix for W2–W5, including
send/stop, monitor/exit and reconnect races. The research two-worker ADR is input,
not a substitute for this production lifecycle decision.

### W2 — Add bounded wire representations and capability coverage

- Audit the target-version sources indexed in [protocol-sources.md](protocol-sources.md).
  Inventory supported flags, monitor operations and required ETF tags before
  implementation; add the reference encodings needed by the selected profile.
- Keep codecs and pure controls in ETF/protocol; transport must not import actor
  or runtime. Bound reference data, reason terms and aggregate decoded storage.
- Add OTP-generated vectors, malformed/truncated inputs, round trips and
  allocation-failure cleanup tests. Review mandatory-capability gaps separately
  from the smallest monitor codec increment.

**Exit:** pure conformance tests pass on provenance-tracked vectors. Do not
advertise optional monitor support before W4's integrated OTP checks pass. If a
flag requires more semantics than the proposed narrow profile implements,
extend that increment or keep the flag disabled; do not redefine the wire flag.

### W3 — Implement one worker identity and PID-directed delivery

- Implement the W1 lifecycle, live-PID/name lookup and bounded discovery exchange
  for one SHA-256 worker. PID-directed requests must reach the same live worker;
  unknown, stopped or stale identities must follow the documented policy.
- Retain owned-copy payloads and one outstanding work request. Preserve existing
  echo/SHA-256 command contracts; expose the new profile explicitly rather than
  silently changing their wire replies.
- Keep the node alive after a controlled worker stop, remove its registration
  and release its owned state. M1 replacement may use external process restart;
  an in-process supervisor is not required.

**Exit:** identity/discovery, exact replies, stop/cleanup, failed startup and stale
PID tests pass. No packet pointer escapes or early-free send/stop race is accepted.

### W4 — Implement BEAM-to-native PID monitors

- Support a BEAM process monitoring a native worker PID; define monitor,
  demonitor and worker-exit controls according to the target OTP versions.
  Native-to-BEAM monitoring remains a follow-up. Registered-name monitoring is
  included because target OTP implementations require both capability flags;
  discovery-name lifetime remains separate from worker-PID lifetime.
- Bound monitor count and metadata bytes; define/test table-exhaustion behavior.
  Test unknown/dead PIDs, duplicate operations, demonitor/exit races, watcher
  disconnect and cleanup. Never drop a required notification silently.
- Emit the appropriate reason for controlled exit. On connection/process loss,
  discard connection-scoped monitor state and let OTP observe loss semantics;
  do not fabricate actor exit or guarantee notification replay after reconnect.
- Test ordering under work saturation with finite timeouts. A paused shared
  stream can delay controls; control traffic is not a speculative-read exemption.
  Unresolved boundedness/liveness behavior blocks enabling the capability.

**Exit:** real OTP 25/26/27 tests using `monitor`/`demonitor` verify `DOWN` PID,
reference and reason, absence of duplicate notifications for an established
monitor, and node survival after controlled worker exit. Advertise only the
implemented capability scope; do not infer links or `gen_server:call` support.

### W5 — Make external recovery a runnable supported example

- Adapt the research owner to discover/monitor worker PID while retaining node
  and owned-Port loss handling. Keep submission non-suspending, one active
  request, bounded payloads, timeouts and explicit caller-side admission limits.
- Define readiness, restart delay/intensity and shutdown cleanup, including the
  owner/controlling-VM crash path rather than only normal `terminate` cleanup.
  On uncertain completion, fail the request and discard the old connection/process
  before accepting replacement replies; no automatic replay or exactly-once claim.
- Exercise controlled worker exit, native SIGKILL, injected panic/allocation
  failure, noncooperative spin, connection loss and private EPMD loss. Fault
  injection stays test-only; kill only test-owned processes.

**Exit:** repeated bounded recovery trials obtain a fresh PID and exact result,
reject stale identities/replies, preserve the BEAM VM and an unrelated process,
and leave no owned child behind after shutdown. Review native Linux execution,
secret handling and deployment boundaries before a production support claim.

## After M1 — M2: a small task-owning actor runtime

M2 connects bounded mailboxes and the registry to runtime-owned `std.Io` tasks,
using an API with explicit lifecycle migration notes. Start with two actors;
prove task joining, queued-message cleanup, safe send/terminate races and
independent progress when one actor waits. Do not promise preemption of arbitrary
CPU-bound Zig code or actor-local panic/corruption isolation.

Review shared-wire routing/admission before adding destinations: unknown next
routes cannot use summed free capacity. Accept documented head-of-line blocking
before introducing a pending queue. Verify monitor behavior across local actor
stop/replacement and node loss again with the concurrent runtime.

Process links and native supervision require subsequent explicit semantics and
OTP/fault tests. External supervision remains usable without either. Custom
work-stealing, tracing GC, arenas, snmalloc, io_uring, batching and zero-copy are
not M1/M2 prerequisites. Performance work resumes only against a stable baseline.

## Verification and documentation gates

- Run `test-unit`, `test-integration`, `test-conformance`, `test-stress` and
  `test-all` with the pinned compiler; record Debug and ReleaseSafe results.
- For wire changes, run the pinned OTP 25/26/27 matrix and new monitor cases;
  skipped/unavailable targets are not passes. Review deployment-supported OTP
  versions separately from the retained compatibility regression matrix.
- Record exact commands, compiler/OTP/OS, bounds, timeouts and raw results in
  Phase B for wire conformance and Phase C for runtime/fault behavior. No old
  branch log proves a new integrated tree correct.
- Update [implementation-status.md](implementation-status.md),
  [research-needed.md](research-needed.md) and the relevant
  [design-target sections](../specs/zbeam-v0.5.0.md) with each implemented
  lifecycle/protocol increment; planning alone changes no implementation status.

**Next action:** W0's commit inventory and integrated regression baseline, then
W1's lifecycle ADR. The first new feature is bounded identity/monitor support,
not a general scheduler or another performance comparator.

## Acceptance policy

Correctness and boundedness are mandatory; performance gains are optional. A regression in cancellation, allocation ownership, pressure limits or protocol conformance blocks promotion even if a benchmark improves.

The snmalloc plan proposes performance/memory thresholds before measurements. Those are decision criteria, not observed results or release SLOs. Other performance changes require the same predeclared workload and regression budget.

The implementation truth table remains [implementation-status.md](implementation-status.md). Unresolved risks remain [research-needed.md](research-needed.md). This plan orders work; it does not mark the remaining work as implemented.
