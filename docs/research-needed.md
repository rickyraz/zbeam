# Research and Risk Backlog

**Reviewed:** 2026-09-26. The [single-actor MVP](mvp.md) is implemented; the full v0.5 design is not. [Implementation status](implementation-status.md) distinguishes executed evidence from proposals.

The [development plan](development-plan.md) defines execution order and final release gates. The [snmalloc evaluation](snmalloc-evaluation.md) specifies the allocator experiment without changing the default build.

## Priority labels

- **P0 — restricted MVP gate:** required for the documented single-actor development profile.
- **P1 — expansion/correctness gate:** required before broader compatibility, concurrency or deployment claims.
- **P2 — optimization research:** considered after a measured need and a correct portable implementation.

## Closed P0 work

| Work | Scope of completion | Evidence |
|---|---|---|
| Protocol source audit | ETF/EPMD/handshake/pass-through subset and fixtures; not all protocol operations | `protocol-sources.md`, conformance suite |
| One-actor interoperability | Actual OTP 25/26/27, both handshake directions, exact messages, bad cookies, idle ticks and reconnect | Phase B 2026-09-26; pinned matrix runner |
| Bounded demand-driven service | No read/allocation at zero credits; no prefetch; per-term allocation budgets; copied ownership | Unit/integration tests; Phase C TCP stress |
| Connection failure isolation | Invalid/unsupported frames close a peer; subsequent peers work; SIGKILL yields nodedown without taking down OTP | Integration and OTP matrix |
| Port baseline | Same 32-byte sequential workload; latency percentiles, throughput, memory snapshots, one restart sample, scheduler activity and raw samples | Phase C 2026-09-26 baseline |

Completion is deliberately limited to the MVP scope. It does not close the broader items below.

## P1 — Next implementation work

### Transport deadlines and liveness diagnostics

**Risk:** the service accepts one peer at a time. An incomplete handshake/frame, blocked writer or nonreturning handler can occupy it indefinitely. Zero demand also pauses heartbeat processing. EPMD socket loss is not actively detected.

**Required evidence:** bounded handshake/read/write deadlines using `std.Io` cancellation, stalled-handler diagnostics with no fabricated demand, tests for cancellation in every wait state, and an explicit policy for EPMD loss. Preserve the zero-read invariant rather than introducing a heartbeat-prefetch exception.

### Mandatory ETF capability coverage

**Risk:** modern OTP requires baseline handshake flags for encodings beyond the MVP decoder. The profile rejects unsupported matching payloads and is not a general-compatible node.

**Required evidence:** add tags and their bounds incrementally, with real OTP vectors, malformed-input tests and allocation-failure cleanup. Negotiate optional capabilities only when implemented. Full atom character/byte semantics must be distinguished from the current 255-byte policy.

### Protocol control and actor addressing

Implement process links/monitors, registered-name monitoring, PID-directed local delivery and any required OTP service protocols only with explicit semantics and black-box checks. Published-node housekeeping is currently ignored when addressed to unknown registered names; there is no distributed `global` implementation. Do not infer `gen_server:call` or `net_adm:ping` support from a successful handshake.

### Mailbox task ownership and lifetimes

Bounded queue operations, logical token ownership, concurrent-receive exclusion, duplicate mailbox registration and close/drain behavior are implemented. Tokens remain copyable and publicly constructible. Callers must join all operations before destroying mailbox storage or the registry, including sends that resolved a mailbox before termination.

**Required evidence for expansion:** task-bound identity or a documented capability alternative, register/terminate/send races with a stronger lifetime strategy, shutdown wakeup coverage, and sanitizer runs where supported. Registry locking alone does not extend external pointer lifetimes.

### Observable BEAM-side backpressure

A real TCP sender is stopped during a paused handler and completes after progress resumes. This establishes transport backpressure, not how a BEAM distribution sender, port queue or process scheduler behaves under saturation.

**Required evidence:** a fast OTP sender, a slow actor, distribution queue/memory measurements, bounded pause windows and externally observed sender throttling. Report normal pauses separately from actor failures.

### Reconnect and incarnation expansion

Current behavior discards all per-connection packets/demand and generates a fresh challenge on sequential reconnect. The running node retains its EPMD creation; restarted nodes register anew. There is no outbound backoff or replay.

**Required evidence:** restart/creation changes, stale PID handling, simultaneous connections, interrupted outbound requests, and fragment/cache cleanup if those features are introduced. Never carry old demand or partially decoded state into a new connection.

### Fragment and allocation bounds

The MVP rejects cached/fragmented headers, checks wire lengths before allocation and caps aggregate owned storage per decoded term. It has no fragment assembler.

**Required evidence for fragments:** message-size, fragment-count, assembly-count, total memory and timeout bounds, with interruption/reconnect tests before advertising fragment support.

### Actor failure blast radius

SIGKILL process-loss checks pass with a surviving BEAM VM and unrelated local process. This is not a panic, allocator-failure or deliberate memory-corruption campaign and does not isolate actors inside one native process.

**Required evidence:** separate fault-injection cases in test-only executables, bounded nodedown observation, leak/resource cleanup where applicable and externally supervised restart behavior. No fault-injection endpoint belongs in the production service.

### Broader baseline and deployment

The committed Port comparison is a single sequential payload/workload on one host, with scheduler-wall-time instrumentation and memory snapshots. The source audit identifies `DebugAllocator` in the no-libc ReleaseSafe zbeam build; the Port payload path uses fixed storage. These results do not isolate allocator cost. Restart includes orderly shutdown, launch, readiness polling and first reply; it is one sample, not a distribution or crash-recovery SLO.

**Required evidence:** larger payloads, concurrent clients, repetitions/confidence intervals, ordering effects, allocator profiles, loaded BEAM workloads and operational restart policies. Production work also requires non-argv cookie handling, TLS/trusted-network policy and security review.

## P1 — Ownership design before implementation

### Arena identity and recycling

Determine whether identity requires `{connection, slot, generation}`. A final release followed by a separate reset can overwrite a concurrent new claim; the v0.5 pseudocode is not a proof of safe reclamation. Tests must establish that live handles prevent reuse and stale generations are rejected.

### Handle lifecycle and access

Define borrowed, owned, promoted, forwarded and dropped states. An atomic consumed flag does not protect a slice already returned by `access()` against concurrent transfer/recycling. Copying an atomic-containing handle also does not provide linear ownership. Cover concurrent promotion, access/transfer overlap, double/missing drop and cancellation.

### Static API claims

Zig wrapper fields are accessible; removing an `access()` method while exposing an inner handle does not prove byte access impossible. Any forward-only or task-token enforcement claim needs actual compile-failure and escape tests. Historical specification comments must not be treated as language guarantees.

### Representation and battery boundary

The current representation uses owned copies. Compare that baseline with ownership transfer and arena-backed payloads only after measuring a bottleneck. No raw slice may cross an actor/async boundary without an explicit lifetime strategy. No ETF re-encoding is a different claim from zero-copy transfer.

## P2 — Deferred optimization research

### Allocator selection and snmalloc

**Standard baseline evidence:** the [2026-09-27 branch experiment](evidence/phase-c/2026-09-27-allocator-baselines.md) compares explicit standard allocators, linkage and three payload sizes. It does not establish the best external backend or remove the transport/liveness backlog.

**Hypothesis:** batched remote frees may benefit future owned-message producer/consumer workloads. The synchronous MVP does not establish that workload or an allocator bottleneck.

**Risks:** linking libc changes Zig's default allocator selection; preload may affect the benchmark harness without replacing the static zbeam allocator; alignment/OOM/resize semantics, mixed allocator domains, thread/TLS teardown, remote-free retention and added C++ build requirements require validation.

**Required evidence:** explicit standard-allocator baselines, allocation-routing checks, a pinned namespaced C ABI adapter, ownership/cancellation/producer-exit tests, repeated service measurements and peak/post-idle memory results. Promotion requires a separate decision against the [predeclared evaluation gates](snmalloc-evaluation.md#e3--promotion-decision). The [source audit](evidence/phase-a/2026-09-26-allocator-source-audit.md) does not establish integration or performance.

**Experimental outcome:** [snmalloc branch measurements](evidence/phase-c/2026-09-27-snmalloc.md) pass the checks performed here but fail the default-promotion memory/tail gates. Retained-memory/reclamation policy, native-host repetitions, useful workloads and broader fault/sanitizer campaigns remain open. No default switch is justified.

### Other measured-need optimizations

- **Copy threshold/buffer sizing:** use measured payload distributions rather than copying a BEAM constant without workload evidence.
- **io_uring registered buffers:** prove descriptor/buffer ownership, cancellation, exhaustion and fallback before replacing portable `std.Io`.
- **Fan-out demand composition:** define fairness, broadcast/partition semantics and slow-consumer behavior; zero-copy broadcast remains excluded.
- **Per-scheduler arenas:** require demonstrated shared-arena contention before partitioning.
- **Session/linear-type experiments:** keep experiments outside production batteries and distinguish static guarantees from runtime checks.

## Completion rule

Each completed behavior requires implementation, an executable regression and verification evidence under `docs/evidence/`. Remaining work is not complete merely because an earlier MVP gate passed or a specification says that it is fixed.
