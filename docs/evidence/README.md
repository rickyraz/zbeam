# Verification Evidence

Evidence records support implementation and compatibility claims. Passing tests without preserved inputs or environment details is not sufficient for protocol, safety, or performance claims.

## Current MVP records

- [2026-09-26 protocol and OTP matrix](phase-b/2026-09-26-mvp.md)
- [2026-09-26 runtime, backpressure and Port baseline](phase-c/2026-09-26-mvp-runtime.md)

These records supersede earlier pending-matrix/demand status for the restricted MVP. Historical files remain unchanged; the full v0.5 design is still unimplemented.

## Allocator research

- [2026-09-26 allocator source and binary audit](phase-a/2026-09-26-allocator-source-audit.md) — baseline selection/linkage and pinned snmalloc source findings, not snmalloc integration or performance evidence.
- [Evaluation plan](../snmalloc-evaluation.md) — proposed experiment and promotion criteria.
- [Standard allocator baseline](phase-c/2026-09-27-allocator-baselines.md) — branch evidence, unchanged default.
- [Request-local arena experiment](phase-c/2026-09-28-request-arena.md) — opt-in synchronous ownership/cap and matched results; does not promote a default. The separate snmalloc results live on `explore/snmalloc` (`62c511c`).

## Phases

- `phase-a/` — local logic, type/API contract, and compile-fail evidence.
- `phase-b/` — integration, wire fixtures, and real OTP interoperability.
- `phase-c/` — concurrency, network failure, liveness, boundedness, and performance stress.

## Required record fields

Each record identifies the commit, date, environment, commands, expected result, actual result, and related requirement or ADR. Packet captures and raw benchmark files must be referenced without embedding credentials or Erlang cookies.

A design document cannot cite a planned test as completed evidence.
