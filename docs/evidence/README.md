# Verification Evidence

Evidence records support implementation and compatibility claims. Passing tests without preserved inputs or environment details is not sufficient for protocol, safety, or performance claims.

## Current MVP records

- [2026-09-26 protocol and OTP matrix](phase-b/2026-09-26-mvp.md)
- [2026-09-26 runtime, backpressure and Port baseline](phase-c/2026-09-26-mvp-runtime.md)
- [2026-09-28 handshake deadline](phase-b/2026-09-28-handshake-deadline.md)
- [2026-09-28 frame/EPMD liveness](phase-c/2026-09-28-connection-liveness.md)
- [2026-09-28 SHA-256 native worker](phase-c/2026-09-28-sha256-worker.md)

These records supersede earlier pending-matrix/demand status for the restricted MVP. Historical files remain unchanged; the full v0.5 design is still unimplemented.

## Monitorable native worker — M1

- [2026-10-25 references and monitor wire evidence](phase-b/2026-10-25-m1.md)
- [2026-10-25 worker lifecycle, OTP matrix and external recovery](phase-c/2026-10-25-m1.md)

These records cover the bounded development profile, not a general actor
scheduler or production release.

## Compiler migration readiness

- [2026-10-25 Zig 0.17 probe and all-branch inventory](phase-a/2026-10-25-zig-0.17.md) — migration remains planned; no 0.17 acceptance claim.

## Allocator research

- [2026-09-26 allocator source and binary audit](phase-a/2026-09-26-allocator-source-audit.md) — baseline selection/linkage and pinned snmalloc source findings, not snmalloc integration or performance evidence.
- [Evaluation plan](../snmalloc-evaluation.md) — proposed experiment and promotion criteria.

## Phases

- `phase-a/` — local logic, type/API contract, and compile-fail evidence.
- `phase-b/` — integration, wire fixtures, and real OTP interoperability.
- `phase-c/` — concurrency, network failure, liveness, boundedness, and performance stress.

## Required record fields

Each record identifies the commit, date, environment, commands, expected result, actual result, and related requirement or ADR. Packet captures and raw benchmark files must be referenced without embedding credentials or Erlang cookies.

A design document cannot cite a planned test as completed evidence.
