# Research and Risk Backlog

**Reviewed:** 2026-10-26. The [single-actor MVP](mvp.md) and bounded M1 profile are accepted; task-owning M2 and the full v0.5 design are not implemented. [Implementation status](implementation-status.md) distinguishes executed evidence from proposals.

The [development plan](development-plan.md) defines execution order and final release gates. The [snmalloc evaluation](snmalloc-evaluation.md) specifies the allocator experiment without changing the default build.

## Compiler migration boundary — 2026-10-26

[All 14 migration candidates](evidence/phase-a/2026-10-26-zig-0.17-rollout.md)
passed their own native, OTP, eligible-NIF and allocator/lifetime gates. The
[authorized handover](evidence/phase-a/2026-10-26-branch-consolidation.md) merged
compiler PR #2 and retained eleven local/remote branches. M1 was subsequently
accepted through PR #3 and cleanup repair PR #4; all nine research topics remain
independent of master. Exact archives and ignored assets are
preserved; no other live Pi checkout was switched. Zigler requires an unreleased exact
Git pin; threaded NIF teardown remains quarantined. Explicit DebugAllocator is
still supported but deprecated, separate from startup's SafeAllocator in
0.17 debug/safe even with libc. Historical 0.16 results are not new-compiler
allocator/performance evidence. Production, long-soak and non-Linux gates remain
open. Actual compiler PR/merge and handover CI were observed; current tip checks
remain necessary. [M1 acceptance triage](evidence/phase-b/2026-10-26-m1-acceptance.md)
reproduces a source-supported EPMD daemon-exit/readiness race and closes that
launcher gap, including forced probe cleanup. The original runner's exact trace
remains unavailable; no native retry or historical-cause certainty is claimed.
Explicit size-exception approval, candidate/PR checks and actual repaired-master
CI closed [M1 acceptance](evidence/phase-b/2026-10-26-m1-integration.md). The
post-merge Port cleanup failure and repair remain recorded, not rerun away.
This closes the bounded M1 gate, separately from all nine research topics.

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

**Current boundary (2026-09-28):** the runtime has a five-second total handshake budget; partial NAME/REPLY and silent initiating peers expire and the next peer succeeds. Direct transport callers may set their own budget; `null` remains an explicit unbounded override. [Verification](evidence/phase-b/2026-09-28-handshake-deadline.md).

**Current boundary (2026-09-28):** the runtime now bounds one frame read to 90 seconds and one reply write to five seconds; a synthetic registration-socket loss makes the executable stop rather than serve an undiscoverable node. The [connection-liveness record](evidence/phase-c/2026-09-28-connection-liveness.md) covers partial-frame recovery, blocked writer cleanup, real OTP and synthetic EPMD loss. Neither timer reads without demand or safely preempts arbitrary handler code.

**Risk:** one nonreturning handler still monopolizes the peer. Demand pauses ticks and may prompt a BEAM-side disconnect. The 90-second idle/partial-frame timeout does not distinguish slowloris data from a silent peer, and the CLI fail-stops on EPMD loss rather than re-registering.

**Required evidence:** stalled-handler diagnostics, separate idle/partial deadlines and externally observed tick policy, controlled error/OOM during each wait, EPMD restart and re-registration policy. Preserve the zero-read invariant instead of introducing heartbeat-prefetch.

### Mandatory ETF capability coverage

**Additive boundary (2026-10-25):** bounded newer/legacy references and pure
PID/named-monitor controls have tests and OTP 25/26/27 reference vectors. Flags
were disabled at the codec-only checkpoint; the accepted worker profile enables
both flags after integrated W4 checks. Other mandatory tag coverage remains
unresolved; references/monitors do not establish general ETF conformance.

**Risk:** modern OTP requires baseline handshake flags for encodings beyond the MVP decoder. The profile rejects unsupported matching payloads and is not a general-compatible node.

**Required evidence:** add tags and their bounds incrementally, with real OTP vectors, malformed-input tests and allocation-failure cleanup. Negotiate optional capabilities only when implemented. Full atom character/byte semantics must be distinguished from the current 255-byte policy.

### Protocol control and actor addressing

M1 implements bounded BEAM-to-native PID/named monitors and PID-directed delivery
for one worker. Process links, outbound monitors, generic multi-actor routing and
OTP service protocols remain separate work requiring explicit semantics and
black-box checks. Published-node housekeeping is currently ignored when addressed to unknown registered names; there is no distributed `global` implementation. Do not infer `gen_server:call` or `net_adm:ping` support from a successful handshake.

### Mailbox task ownership and lifetimes

Bounded queue operations, logical token ownership, concurrent-receive exclusion, duplicate mailbox registration and close/drain behavior are implemented. Tokens remain copyable and publicly constructible. Callers must join all operations before destroying mailbox storage or the registry, including sends that resolved a mailbox before termination.

**Required evidence for expansion:** task-bound identity or a documented capability alternative, register/terminate/send races with a stronger lifetime strategy, shutdown wakeup coverage, and sanitizer runs where supported. Registry locking alone does not extend external pointer lifetimes.

### Observable BEAM-side backpressure

A real TCP sender is stopped during a paused handler and completes after progress resumes. This establishes transport backpressure, not how a BEAM distribution sender, port queue or process scheduler behaves under saturation.

**Required evidence:** a fast OTP sender, a slow actor, distribution queue/memory measurements, bounded pause windows and externally observed sender throttling. Report normal pauses separately from actor failures.

### Reconnect and incarnation expansion

**Worker identity risk (2026-10-25):** `serve-worker` retains one PID across TCP
reconnect and never reuses it within that service. Across process replacement,
EPMD creation and a randomized 64-bit ID/serial provide practical separation,
not persistent absolute uniqueness if EPMD state is lost/reused. No persistent
identity allocator or general in-process actor replacement is implemented.

**External deployment boundary (2026-10-25):** the Linux monitored-owner example
verifies Port/owner/VM cleanup and bounded work admission, not arbitrary forking
process trees, TLS or secret delivery. Its finite run uses fresh node names;
indefinite deployments require bounded atom/name allocation or a stable-name
cleanup barrier. Owner checks currently use Elixir 1.20.4/OTP 29 separately from
wire checks on OTP 25/26/27. Production Elixir/OTP pairings remain to be verified.
OS OOM and memory corruption are not covered by deterministic allocator-failure
and panic fixtures; noncooperative CPU work still requires external termination.

Current behavior discards all per-connection packets/demand and generates a fresh challenge on sequential reconnect. The running node retains its EPMD creation; restarted nodes register anew. There is no outbound backoff or replay.

**Required evidence:** restart/creation changes, stale PID handling, simultaneous connections, interrupted outbound requests, and fragment/cache cleanup if those features are introduced. Never carry old demand or partially decoded state into a new connection.

### Fragment and allocation bounds

The MVP rejects cached/fragmented headers, checks wire lengths before allocation and caps aggregate owned storage per decoded term. It has no fragment assembler.

**Required evidence for fragments:** message-size, fragment-count, assembly-count, total memory and timeout bounds, with interruption/reconnect tests before advertising fragment support.

### Actor failure blast radius

SIGKILL process-loss checks preserve the BEAM VM and unrelated local process.
M1 additionally verifies test-only panic, deterministic allocator failure, spin,
external recovery and owned-process cleanup, including a regression for concurrent
Port closure. This does not establish OS-OOM/memory-corruption safety or isolate
actors inside one native process.

**Required evidence for expansion:** OS-OOM/corruption and native-host soak or
sanitizer coverage where supported; no test endpoint belongs in the production
service. Native task isolation and general in-process supervision remain unimplemented.

### Broader baseline and deployment

The committed Port comparison is a single sequential payload/workload on one host, with scheduler-wall-time instrumentation and memory snapshots. The source audit identifies `DebugAllocator` in the no-libc ReleaseSafe zbeam build; the Port payload path uses fixed storage. These results do not isolate allocator cost. Restart includes orderly shutdown, launch, readiness polling and first reply; it is one sample, not a distribution or crash-recovery SLO.

**Current additional evidence (2026-09-28):** a fixed SHA-256 binary worker has exact OTP 25/26/27 checks, a runnable BEAM client and repeated 32 B/64 KiB Port comparisons. The [SHA-256 record](evidence/phase-c/2026-09-28-sha256-worker.md) retains its negative distribution-latency result. This is one useful computation, not general process/monitor support or a worker-supervision framework.

**Required evidence:** concurrent clients, more useful workload mixtures, confidence intervals, randomized path ordering, allocator/CPU profiles, loaded BEAM workloads and operational restart policies. Production work also requires non-argv cookie handling, TLS/trusted-network policy and security review.

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

**Hypothesis:** batched remote frees may benefit future owned-message producer/consumer workloads. The synchronous MVP does not establish that workload or an allocator bottleneck.

**Risks:** linking libc changes Zig's default allocator selection; preload may affect the benchmark harness without replacing the static zbeam allocator; alignment/OOM/resize semantics, mixed allocator domains, thread/TLS teardown, remote-free retention and added C++ build requirements require validation.

**Required evidence:** explicit standard-allocator baselines, allocation-routing checks, a pinned namespaced C ABI adapter, ownership/cancellation/producer-exit tests, repeated service measurements and peak/post-idle memory results. Promotion requires a separate decision against the [predeclared evaluation gates](snmalloc-evaluation.md#e3--promotion-decision). The [source audit](evidence/phase-a/2026-09-26-allocator-source-audit.md) does not establish integration or performance.

### Other measured-need optimizations

- **Copy threshold/buffer sizing:** use measured payload distributions rather than copying a BEAM constant without workload evidence.
- **io_uring registered buffers:** prove descriptor/buffer ownership, cancellation, exhaustion and fallback before replacing portable `std.Io`.
- **Fan-out demand composition:** define fairness, broadcast/partition semantics and slow-consumer behavior; zero-copy broadcast remains excluded.
- **Per-scheduler arenas:** require demonstrated shared-arena contention before partitioning.
- **Session/linear-type experiments:** keep experiments outside production batteries and distinguish static guarantees from runtime checks.

## Completion rule

Each completed behavior requires implementation, an executable regression and verification evidence under `docs/evidence/`. Remaining work is not complete merely because an earlier MVP gate passed or a specification says that it is fixed.
