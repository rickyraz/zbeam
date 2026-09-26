# Development Plan: MVP to a Supported Native Worker Peer

- **Status:** proposed execution plan, not implemented functionality.
- **Reviewed:** 2026-09-26.
- **Baseline:** `090bb60`, the restricted single-actor MVP.
- **Allocator track:** [snmalloc evaluation](snmalloc-evaluation.md).

## Direction

The product target is a Zig library and separate-process worker node that Erlang/Elixir applications can address, monitor and operate predictably. It is not a replacement BEAM VM, a NIF framework, or an attempt to implement every OTP service.

The differentiator must be useful native worker identities and lifecycle control through distribution, not an unsupported claim that distribution is faster than Ports. The current 32-byte benchmark favors the Port path. It also uses a diagnostic allocator in the ReleaseSafe configuration; allocator and transport costs must be separated before attributing that result.

The supported profile must state its actual ETF tags, control operations, platforms and OTP versions. A release cannot turn the v0.5 historical pseudocode into an implementation claim.

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

Phases are evidence gates, not calendar promises. The allocator investigation can run alongside reliability work in an isolated benchmark target, but it cannot bypass reliability gates or justify speculative scheduler changes.

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

## First implementation increments

Each increment is a separate coherent change with tests and evidence:

1. **Allocator/profiling baseline:** explicit lab allocator choices and backend metadata; repeat existing Port comparison with matched payloads. No snmalloc dependency yet.
2. **Handshake deadline:** partial NAME/REPLY, wrong cookie, cancellation and next-peer recovery; update the lifecycle contract.
3. **Distribution deadline/shutdown:** distinguish idle, incomplete frame, blocked reply and demand pause; prove cleanup before the next connection.
4. **Mandatory ETF/control matrix:** inventory missing tags/operations, then implement the smallest useful set (references/maps/numbers as required by the chosen request protocol) without claiming the rest complete.
5. **snmalloc lab:** pinned source, namespaced C ABI, minimal Zig adapter and allocator-contract/remote-free tests. This can run alongside increments 2–4 but does not alter the main executable by default.
6. **Task/message lifecycle ADR:** specify mailbox storage, ownership transfer, termination and admission before scheduling multiple actors.
7. **Useful worker example and release checklist:** demonstrate work, worker monitoring and restart; choose release support boundaries from the accumulated evidence.

## Acceptance policy

Correctness and boundedness are mandatory; performance gains are optional. A regression in cancellation, allocation ownership, pressure limits or protocol conformance blocks promotion even if a benchmark improves.

The snmalloc plan proposes performance/memory thresholds before measurements. Those are decision criteria, not observed results or release SLOs. Other performance changes require the same predeclared workload and regression budget.

The implementation truth table remains [implementation-status.md](implementation-status.md). Unresolved risks remain [research-needed.md](research-needed.md). This plan orders work; it does not mark the remaining work as implemented.
