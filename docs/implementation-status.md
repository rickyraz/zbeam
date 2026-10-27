# Implementation Status

- **MVP baseline:** 2026-09-26; reliability and SHA-256 worker extensions verified 2026-09-28
- **Compiler migration:** Zig 0.17.0 verified 2026-10-25; M1 runtime scope unchanged
- **All-branch verification:** [14/14 profiles](evidence/phase-a/2026-10-26-zig-0.17-rollout.md) verified and archived; [consolidation executed](evidence/phase-a/2026-10-26-branch-consolidation.md), 28 to 11 local/remote names. Compiler PR #2 and M1 PR #3 are merged; nine protected research topics remain independent.
- **Package version:** 0.0.1 pre-alpha (no release tag created)
- **Implemented milestone:** restricted MVP, bounded monitorable-worker M1, and local fixed-task M2a
- **M1 accepted into master — 2026-10-26:** owner approved `size:exception`; PR #3 merged as `2241e7f`, followed by cleanup repair PR #4 as `88db721`. [Actual repaired-master CI 40354417903](https://github.com/rickyraz/zbeam/actions/runs/40354417903) passed 9/9 jobs, including all six native OTP/mode lanes and 14 complementary recovery cases per mode. [Acceptance record](evidence/phase-b/2026-10-26-m1-integration.md); earlier failures remain preserved. Local M2a is subsequently accepted; M2b wire expansion remains pending.
- **Broader design target:** v0.5.0 draft, not a release description
- **M2a accepted — 2026-10-27:** local task ownership at `221a48d`; [actual-master CI 40468839059](https://github.com/rickyraz/zbeam/actions/runs/40468839059) passed 9/9 jobs. [Acceptance evidence](evidence/phase-c/2026-10-27-m2a-acceptance.md) separates local implementation from unchanged M1 wire regressions.
- **Next phase:** [M2b wire design](adr/0005-two-worker-wire-profile.md) is proposed. Its [internal session dispatcher](evidence/phase-a/2026-10-27-m2b-session-dispatch.md) composes read admission, decoding, output and monitoring, but is not connected to a socket service; epoch teardown and wire compatibility remain open. Full M2 and production acceptance are not established.

This file is authoritative when code and historical specifications differ.

## Implemented and verified

| Area | Current contract | Verification |
|---|---|---|
| Packaging | Zig 0.17.0; five independent batteries and a behavior-free umbrella; ADR 0001 dependency DAG | Independent unit builds and integration imports |
| ETF | Owned integer/UTF-8 atom/tuple/binary/proper list/nil/NEW_PID/reference subset; depth, size and aggregate allocation limits | Unit, golden-vector and conformance tests |
| EPMD | Registration-socket ownership; node lookup; fail-stop executable when registration socket closes | Deterministic socket-loss test and real OTP discovery/removal |
| Handshake | Initiating and accepting OTP 23+ format; mutual cookie digest; no read-ahead loss at distribution handoff | Coalesced-frame regression, partial NAME/REPLY and silent-initiator deadline tests; actual OTP 25/26/27 |
| Distribution | Bounded pass-through framing, ticks, REG_SEND and SEND subset | Conformance and socket integration |
| Runtime service | One synchronous registered echo or SHA-256 binary worker per process; repeat messages; sequential peers; fresh per-connection state | `serve`, `serve-sha256`, integration and OTP matrix |
| Initiating request | `probe` discovers an OTP peer, authenticates identity and validates one exact SEND reply | Synthetic housekeeping/tick regression and OTP matrix |
| Demand | One outstanding frame; atomic reservation before unbuffered read; credit restored after handler/reply; 90-second frame and five-second write budgets | Zero-read/allocation oracle, partial-frame recovery, blocked-writer and pause/resume tests |
| Local actors | Bounded MPSC mailbox; blocking delivery plus nonblocking `tryDeliver` (`WouldBlock`, no pending putter); logical consumer token; concurrent receive rejection; caller-owned registry and termination | Unit and eight-producer stress tests |
| Process-loss boundary | Test child SIGKILL produces OTP nodedown without terminating the VM or an unrelated local process | OTP 25/26/27 black-box assertions |
| Benchmark | Original 32-byte echo baseline retained; new 32 B/64 KiB SHA-256 versus Port comparison with exact digest checks | Reproducible scripts and raw Phase C records |

The [handshake deadline record](evidence/phase-b/2026-09-28-handshake-deadline.md), [connection-liveness record](evidence/phase-c/2026-09-28-connection-liveness.md), and [SHA-256 worker record](evidence/phase-c/2026-09-28-sha256-worker.md) cover the extensions. Details and commands for the original MVP are in [mvp.md](mvp.md). Verification records are [Phase B](evidence/phase-b/2026-09-26-mvp.md) and [Phase C](evidence/phase-c/2026-09-26-mvp-runtime.md).

## M1 wire foundations — 2026-10-25

Bounded NEWER_REFERENCE_EXT (1–5 words), legacy NEW_REFERENCE_EXT (1–3 words,
legacy significant-bit checks), value-based PID/reference equality and pure
PID/named monitor control parsing are additive. Reference vectors match actual OTP
25/26/27. Monitor negotiation is enabled only for the separately tested worker
profile. See [wire evidence](evidence/phase-b/2026-10-25-m1.md).

## M1 worker identity — 2026-10-25

The explicit `serve-worker` profile supports correlated discovery, PID-directed
bounded SHA-256, normal stop and stale-PID rejection across sequential peers.
Controlled worker stop preserves the node. There is no task scheduler or automatic
in-process replacement. Debug/ReleaseSafe and OTP 25/26/27 tests cover the new
profile. PID and named discovery-endpoint monitoring use a shared fixed table
of 64 subscriptions per connection; unknown/stopped targets report `noproc`.
Normal stop emits `normal` only for worker-PID monitors; discovery-name monitors
survive it. Demonitor, idempotence, table exhaustion, failed writes and allocation
cleanup have regressions. Actual OTP tests distinguish process `DOWN` from
connection `noconnection` and check reference/PID/reason and duplicate absence.
[Runtime evidence](evidence/phase-c/2026-10-25-m1.md).

## M1 external recovery example — 2026-10-25

The [Linux owner example](worker-recovery.md) discovers/monitors the worker,
bounds public hash admission, fails uncertain work without replay and restarts
under an external Elixir supervisor. A guarded child process has independent
owner/VM-crash cleanup. The opt-in `test-worker-recovery` target covers startup
failure, normal stop, native/guardian/owner/VM loss, caller admission/death,
timeout, stale references, restart intensity and private EPMD loss. Panic,
allocation failure and spin are test-only fixtures, never production endpoints.
Owner tests use Elixir 1.20.4 / OTP 29; wire interoperability remains independently
verified on OTP 25/26/27. This is not a production deployment certification.

## M2a local task ownership — accepted 2026-10-27

[TaskRuntime](task-runtime.md) now owns two fixed SHA-256 tasks, copied inputs,
completion-held admission and stable mailbox storage. Startup rollback joins all
started tasks; stop/join/shutdown drain before deinit, which refuses early free.
Basic digest/identity/cleanup and first/second-start failure tests pass.
[Deterministic lifecycle tests](evidence/phase-c/2026-10-27-m2a-lifecycle.md)
cover stop/cancel before claim, saturation, handler error and independent progress.
The [subprocess watchdog](evidence/phase-c/2026-10-27-m2a-shutdown-watchdog.md)
verifies stalled join and external kill/reap, not preemption.
The [production-mode example/public API stress](evidence/phase-c/2026-10-27-m2a-public-api.md)
and [actual-master acceptance](evidence/phase-c/2026-10-27-m2a-acceptance.md)
close local T0–T4 only. M2b routing is not implemented; existing `Runtime(T)`
and all M1 network services remain unchanged.

## Not implemented or not established

- Complete ETF coverage, old handshakes, simultaneous-connection arbitration or general Erlang-node compatibility.
- Cached distribution headers, fragmentation, proactive heartbeat scheduling or control operations beyond the documented send/monitor subset.
- Distributed registry semantics, RPC, OTP behaviours, process links, outbound process monitors, built-in native supervision or a general actor task scheduler. `sha256` is one fixed registered worker, not a general job system.
- Concurrent peer servicing, stalled-handler recovery, outbound reconnect/backoff or EPMD re-registration. The executable instead fails closed on EPMD loss; no CPU-bound handler preemption or proactive heartbeat exists.
- Arena-backed buffers, `BufferHandle`, typestate/linear ownership, io_uring or zero-copy transfer.
- snmalloc integration or allocator-comparison results; the [evaluation plan](snmalloc-evaluation.md) and source audit are research only.
- BEAM distribution-sender throttling measurements, multi-workload performance conclusions or isolation between actors inside the native process.
- Memory-corruption/OS-OOM injection, sanitizers/TSAN or a production security audit. Test-only panic and deterministic allocation-failure recovery are covered.

The service deliberately uses synchronous owned-copy processing. The reusable mailbox/registry is not an implicit asynchronous scheduler. Logical tokens are copyable; they do not prove an OS-thread or task identity. Caller-managed lifetimes remain required.

## Zig 0.17 compiler migration

The current build uses 0.17's `addPassthruArgs` and optimizer values
`debug`/`safe`/`fast`/`small`; old `ReleaseSafe` command-line values are not accepted.
Fixed repeated arrays use typed `@splat`, retaining existing stress/lab assertions.
Core, labs and both intentional compile failures pass in debug/safe; actual OTP
25/26/27 and run/benchmark argument forwarding also pass. No runtime/protocol
feature is added by the migration. [Canonical evidence](evidence/phase-a/2026-10-25-zig-0.17-master.md)
and [combined M1 gates](evidence/phase-a/2026-10-25-zig-0.17-monitorable-worker.md)
record the distinct source snapshots and runtime/owner checks.

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
