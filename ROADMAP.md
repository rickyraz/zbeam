# Roadmap

zbeam advances only when a milestone leaves executable evidence. The v0.5 specification is a design backlog, not a release description.

## M0 — Honest public scaffold

- [x] English project entry points and contribution policy
- [x] Explicit spec-to-code status
- [x] Zig 0.16.0 CI and test-suite wiring
- [ ] First tagged pre-alpha release

## M1 — Minimum real distribution peer

- [ ] ETF fixtures for the smallest required term subset
- [ ] EPMD registration and lookup
- [ ] Initiating and accepting OTP 25–27 handshakes
- [ ] One registered Zig actor reachable from Elixir/Erlang
- [ ] Black-box round-trip test against a real OTP node

**Exit evidence:** one actor exchanges a documented message with OTP; captured bytes match the official protocol documentation.

## M2 — Correct runtime boundary

- [ ] Thread-safe, single-consumer mailbox contract
- [ ] Link/monitor behavior verified from OTP
- [ ] Bounded message and fragment handling
- [ ] Reconnect and incarnation cleanup
- [ ] Demand-gated receive path with observable TCP backpressure

**Exit evidence:** logic, integration, conformance, and stress suites pass; bounded-memory and failure behavior are recorded under `docs/evidence/`.

## M3 — Validate the niche

- [ ] Compare one zbeam actor with one Erlang Port
- [ ] Measure p50/p95/p99 latency, memory, restart time, and BEAM scheduler impact
- [ ] Add two or three actors only after the one-actor baseline is useful
- [ ] Document the actual failure blast radius inside one zbeam process

**Exit evidence:** reproducible benchmark scripts and raw results, including negative results.

## M4 — Ownership optimization

- [ ] Copy small binaries by default
- [ ] Prove arena slot claim/release correctness under contention
- [ ] Add explicit owned/borrowed/forward-only APIs only where tests justify them
- [ ] Verify no stale slot reuse or silent refcount underflow

## Deferred

- io_uring registered-buffer fast path
- zero-copy broadcast fan-out
- general linear/session-type enforcement
- per-scheduler arena partitioning

These remain deferred until the portable path is correct and measured.
