# Implementation Status

- **MVP baseline:** 2026-09-26; reliability and SHA-256 worker extensions verified 2026-09-28
- **Compiler migration:** Zig 0.17.0 native and eligible NIF gates are recorded separately from historical measurements
- **Package version:** 0.0.1 pre-alpha (no release tag created)
- **Implemented milestone:** [restricted single-actor MVP](mvp.md)
- **Broader design target:** v0.5.0 draft, not a release description
- **Proposed next phases:** [development plan](development-plan.md); planning does not change this implementation inventory

This file is authoritative when code and historical specifications differ.

## Implemented and verified

| Area | Current contract | Verification |
|---|---|---|
| Packaging | Zig 0.17.0; five independent batteries and a behavior-free umbrella; ADR 0001 dependency DAG | Independent unit builds and integration imports |
| ETF | Owned integer/UTF-8 atom/tuple/binary/proper list/nil/NEW_PID subset; depth, size and aggregate allocation limits | Unit, golden-vector and conformance tests |
| EPMD | Registration-socket ownership; node lookup; fail-stop executable when registration socket closes | Deterministic socket-loss test and real OTP discovery/removal |
| Handshake | Initiating and accepting OTP 23+ format; mutual cookie digest; no read-ahead loss at distribution handoff | Coalesced-frame regression, partial NAME/REPLY and silent-initiator deadline tests; actual OTP 25/26/27 |
| Distribution | Bounded pass-through framing, ticks, REG_SEND and SEND subset | Conformance and socket integration |
| Runtime service | One synchronous registered echo or SHA-256 binary worker per process; repeat messages; sequential peers; fresh per-connection state | `serve`, `serve-sha256`, integration and OTP matrix |
| Initiating request | `probe` discovers an OTP peer, authenticates identity and validates one exact SEND reply | Synthetic housekeeping/tick regression and OTP matrix |
| Demand | One outstanding frame; atomic reservation before unbuffered read; credit restored after handler/reply; 90-second frame and five-second write budgets | Zero-read/allocation oracle, partial-frame recovery, blocked-writer and pause/resume tests |
| Local actors | Bounded MPSC mailbox; logical consumer token; concurrent receive rejection; name registry and termination | Unit and eight-producer stress tests |
| Process-loss boundary | Test child SIGKILL produces OTP nodedown without terminating the VM or an unrelated local process | OTP 25/26/27 black-box assertions |
| Benchmark | Original 32-byte echo baseline retained; new 32 B/64 KiB SHA-256 versus Port comparison with exact digest checks | Reproducible scripts and raw Phase C records |

The [handshake deadline record](evidence/phase-b/2026-09-28-handshake-deadline.md), [connection-liveness record](evidence/phase-c/2026-09-28-connection-liveness.md), and [SHA-256 worker record](evidence/phase-c/2026-09-28-sha256-worker.md) cover the extensions. Details and commands for the original MVP are in [mvp.md](mvp.md). Verification records are [Phase B](evidence/phase-b/2026-09-26-mvp.md) and [Phase C](evidence/phase-c/2026-09-26-mvp-runtime.md).

## Research branch extension — 2026-10-02

This branch adds optional direct Zigler NIF and ETF-over-Port benchmark adapters, not a runtime dependency or production behavior change. Exact-result and allocation-bound tests, a fresh-VM smoke and core/OTP regression checks are recorded in [native comparison evidence](evidence/phase-c/2026-10-02-native-comparison.md). Benchmark OTP 29 is distinct from the supported regression targets. No performance-win or native-host replication claim follows from adapter availability.

## Encoder research candidate — 2026-10-13

On `explore/io-overhead`, ETF exposes a rollback-safe caller-owned `encodeInto` append API and distribution framing avoids two intermediate encoded buffers. [Verified measurements](evidence/phase-c/2026-10-13-frame-profile.md) show fewer allocation calls and a promising 64 KiB echo signal, but SHA-256/tail and native-host promotion gates remain unmet. Owned decoding, demand and finite deadlines remain unchanged.

## Not implemented or not established

- Complete ETF coverage, old handshakes, simultaneous-connection arbitration or general Erlang-node compatibility.
- Cached distribution headers, fragmentation, proactive heartbeat scheduling or control operations beyond the documented send subset.
- Distributed registry semantics, RPC, OTP behaviours, process links/monitors, automatic external supervision or a general actor task scheduler. `sha256` is one fixed registered worker, not a general job system.
- Concurrent peer servicing, stalled-handler recovery, outbound reconnect/backoff or EPMD re-registration. The executable instead fails closed on EPMD loss; no CPU-bound handler preemption or proactive heartbeat exists.
- Arena-backed buffers, `BufferHandle`, typestate/linear ownership, io_uring or zero-copy transfer.
- snmalloc integration or allocator-comparison results; the [evaluation plan](snmalloc-evaluation.md) and source audit are research only.
- BEAM distribution-sender throttling measurements, multi-workload performance conclusions or isolation between actors inside the native process.
- Panic/corruption crash-injection coverage, sanitizers/TSAN or a production security audit.

The service deliberately uses synchronous owned-copy processing. The reusable mailbox/registry is not an implicit asynchronous scheduler. Logical tokens are copyable; they do not prove an OS-thread or task identity. Caller-managed lifetimes remain required.

## Zig 0.17 compiler migration

The current build uses 0.17's `addPassthruArgs` and optimizer values
`debug`/`safe`/`fast`/`small`; old `ReleaseSafe` command-line values are not accepted.
Fixed repeated arrays use typed `@splat`, retaining existing stress/lab assertions.
Core, labs and both intentional compile failures pass in debug/safe; actual OTP
25/26/27 and run/benchmark argument forwarding also pass. No runtime/protocol
feature is added by the migration. [Canonical compiler evidence](evidence/phase-a/2026-10-25-zig-0.17-master.md)
and [pinned Zigler integration](evidence/phase-a/2026-10-25-zig-0.17-zigler.md)
record shared changes. The dependency is an unreleased Git pin; threaded NIFs
remain quarantined and old 0.16 measurements are not relabeled.

The 0.17 startup source selects `SafeAllocator` for debug/safe, independently of
libc linkage. Older 0.16 allocator/performance records below remain historical,
not current performance claims. Current compiler/ELF provenance is in the new
record; no benchmark was re-scored.

## Allocator provenance

The executable passes `std.process.Init.gpa` to the runtime. The [source/binary audit](evidence/phase-a/2026-09-26-allocator-source-audit.md) establishes that the recorded Zig 0.16.0, no-libc ReleaseSafe configuration selects `DebugAllocator`; it is not an explicit `smp_allocator` baseline. The Port worker uses fixed payload storage. This does not attribute the latency gap to allocation, and no snmalloc benchmark has been run.

## Compatibility scope

The checked-in runner passed on real OTP 25, 26 and 27 using pinned Docker images on Linux x86-64. OTP 28 is additional local development evidence. Only the MVP operations are covered; mandatory handshake bits do not establish complete support for every corresponding ETF tag. Unsupported matching payloads are rejected by disconnecting that peer.

No claim is made for all patch versions, other operating systems, or full v0.5 conformance. Historical July records remain historical; missing matrix and demand evidence from those records is superseded by the September records, not retroactively changed.

## Structural boundaries

```text
protocol  -> etf
transport -> protocol, etf
runtime   -> actor, transport, protocol, etf
```

ETF and actor remain independent. Transport accepts an injected credit source without importing the actor battery. Tools, fixtures and OTP runners are verification assets, not runtime dependencies.

## Completion rule

A behavior requires code under the correct battery, a runnable regression check, a verification record and an updated status entry. Design pseudocode, a checked roadmap box or an unavailable/skipped OTP target is not implementation evidence.
