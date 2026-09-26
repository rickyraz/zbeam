# Roadmap

zbeam advances only when a milestone leaves executable evidence. The v0.5 specification is a design backlog, not a release description.

## Restricted MVP — verified 2026-09-26

The [single-actor development profile](docs/mvp.md) passes its acceptance gates: both handshake roles on real OTP 25/26/27, bounded owned messages, demand-gated reads, sequential reconnect, process-loss observation and a reproducible Port baseline. This is a subset milestone, not completion of M2–M4 or the full v0.5 specification.

## Execution plan and final target

The [development plan](docs/development-plan.md) orders the remaining work: explicit allocator/profiling baseline, reliable one-peer lifecycle, honest protocol coverage, a small concurrent runtime, measured optimization, then supported packaging/deployment. These phases refine M2–M4; they are not completed milestones or release-date promises.

The target is a supported, separate-process native worker peer with useful actor identities, bounded ownership/backpressure, observable failure and external supervision. It is not a replacement BEAM VM. The [snmalloc evaluation](docs/snmalloc-evaluation.md) is an optional research track; neither snmalloc, arenas nor zero-copy is a release prerequisite.

## M0 — Honest public scaffold

- [x] English project entry points and contribution policy
- [x] Explicit spec-to-code status
- [x] Zig 0.16.0 CI and test-suite wiring
- [x] Independent battery-module build graph (ADR 0001)
- [ ] First tagged pre-alpha release

## M1 — Minimum real distribution peer

- [x] ETF fixtures for the smallest required term subset
- [x] EPMD registration and lookup
- [x] Initiating and accepting OTP 25–27 handshakes (pinned-image black-box evidence)
- [x] One registered Zig actor reachable from Elixir/Erlang
- [x] Exact black-box round trips against OTP 25, 26 and 27; OTP 28 remains additional development evidence

**Exit evidence:** one actor exchanges a documented message with OTP; captured bytes match the official protocol documentation.

## M2 — Correct runtime boundary

- [x] Thread-safe, single-consumer mailbox contract
- [ ] Link/monitor behavior verified from OTP
- [x] Bounded wire messages and aggregate decoded storage; unnegotiated fragments rejected
- [x] Fresh demand and packet state after sequential TCP reconnect
- [x] Demand-gated receive path with observable TCP sender backpressure and cancellation cleanup
- [ ] Fragment assembly, when negotiated, with explicit global bounds
- [ ] OS-restart/stale-PID incarnation tests and outbound reconnect policy
- [ ] BEAM distribution-sender queue/backpressure measurements
- [ ] Transport deadlines and stalled-handler/EPMD-loss diagnostics

**Exit evidence:** logic, integration, conformance, and stress suites pass; bounded-memory and failure behavior are recorded under `docs/evidence/`.

## M3 — Validate the niche

- [x] Compare one zbeam actor with one Erlang Port (same sequential 32-byte workload)
- [x] Record p50/p95/p99, throughput, memory snapshots, restart sample and scheduler activity
- [x] Audit baseline allocator/linkage from the installed toolchain and binary; no allocator profile implied
- [ ] Compare explicit standard allocators and profile allocation/copy/I/O costs
- [ ] Repeat across payload sizes/concurrency and report uncertainty before performance conclusions
- [ ] Add two or three actors only after the one-actor baseline is useful
- [x] Record external process-loss isolation on OTP 25–27
- [ ] Test panic/corruption failures and document the failure blast radius inside one zbeam process

**Exit evidence:** reproducible benchmark scripts and raw results, including negative results.

## M4 — Ownership optimization

- [x] Use owned copies for all supported binaries in the MVP
- [ ] Evaluate pinned snmalloc through an isolated allocator adapter; preserve a no-C++ default build
- [ ] Record an adopt/retain/reject decision from matched workload, memory and correctness evidence
- [ ] Justify a copy/arena threshold from measurements before introducing the arena path
- [ ] Prove arena slot claim/release correctness under contention
- [ ] Add explicit owned/borrowed/forward-only APIs only where tests justify them
- [ ] Verify no stale slot reuse or silent refcount underflow

## Deferred

- io_uring registered-buffer fast path
- zero-copy broadcast fan-out
- general linear/session-type enforcement
- per-scheduler arena partitioning

These remain deferred until the portable path is correct and measured.
