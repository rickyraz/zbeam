# Implementation Status

- **Last verified:** 2026-09-26
- **Package version:** 0.0.1 pre-alpha (no release tag created)
- **Implemented milestone:** [restricted single-actor MVP](mvp.md)
- **Broader design target:** v0.5.0 draft, not a release description
- **Proposed next phases:** [development plan](development-plan.md); planning does not change this implementation inventory

This file is authoritative when code and historical specifications differ.

## Implemented and verified

| Area | Current contract | Verification |
|---|---|---|
| Packaging | Zig 0.16.0; five independent batteries and a behavior-free umbrella; ADR 0001 dependency DAG | Independent unit builds and integration imports |
| ETF | Owned integer/UTF-8 atom/tuple/binary/proper list/nil/NEW_PID subset; depth, size and aggregate allocation limits | Unit, golden-vector and conformance tests |
| EPMD | Registration-socket ownership; node lookup; exact short error response | Deterministic client wire tests and real OTP discovery/removal |
| Handshake | Initiating and accepting OTP 23+ format; mutual cookie digest; no read-ahead loss at distribution handoff | Coalesced-frame regression in both roles; actual OTP 25/26/27 |
| Distribution | Bounded pass-through framing, ticks, REG_SEND and SEND subset | Conformance and socket integration |
| Runtime service | One synchronous registered echo actor; repeat messages; sequential peers; fresh per-connection state; malformed peer isolation | `serve`, `echo`, integration and OTP matrix |
| Initiating request | `probe` discovers an OTP peer, authenticates identity and validates one exact SEND reply | Synthetic housekeeping/tick regression and OTP matrix |
| Demand | One outstanding frame; atomic reservation before unbuffered read; credit restored after handler/reply | Zero-read/allocation oracle, 64 MiB TCP pause/resume test and cancellation cleanup |
| Local actors | Bounded MPSC mailbox; logical consumer token; concurrent receive rejection; name registry and termination | Unit and eight-producer stress tests |
| Process-loss boundary | Test child SIGKILL produces OTP nodedown without terminating the VM or an unrelated local process | OTP 25/26/27 black-box assertions |
| Benchmark | Same 32-byte sequential payload over Port/distribution; p50/p95/p99, throughput, child RSS/HWM, BEAM memory, restart sample, scheduler activity | Reproducible script and raw Phase C results |

Details and commands are in [mvp.md](mvp.md). Verification records are [Phase B](evidence/phase-b/2026-09-26-mvp.md) and [Phase C](evidence/phase-c/2026-09-26-mvp-runtime.md).

## Not implemented or not established

- Complete ETF coverage, old handshakes, simultaneous-connection arbitration or general Erlang-node compatibility.
- Cached distribution headers, fragmentation, proactive heartbeat scheduling or control operations beyond the documented send subset.
- Distributed registry semantics, RPC, OTP behaviours, process links/monitors or a general actor task scheduler.
- Concurrent peer servicing, transport deadlines, stalled-handler recovery, outbound reconnect/backoff or EPMD-loss recovery.
- Arena-backed buffers, `BufferHandle`, typestate/linear ownership, io_uring or zero-copy transfer.
- snmalloc integration or allocator-comparison results; the [evaluation plan](snmalloc-evaluation.md) and source audit are research only.
- BEAM distribution-sender throttling measurements, multi-workload performance conclusions or isolation between actors inside the native process.
- Panic/corruption crash-injection coverage, sanitizers/TSAN or a production security audit.

The service deliberately uses synchronous owned-copy processing. The reusable mailbox/registry is not an implicit asynchronous scheduler. Logical tokens are copyable; they do not prove an OS-thread or task identity. Caller-managed lifetimes remain required.

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
