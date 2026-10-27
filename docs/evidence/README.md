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
- [2026-10-26 accepted master integration](phase-b/2026-10-26-m1-integration.md) — explicit size approval, normal PR #3/#4 merges and actual repaired-master 9/9 CI; M2 and production remain out of scope.
- [2026-10-26 pre-acceptance EPMD readiness triage and local gates](phase-b/2026-10-26-m1-acceptance.md) — historical checkpoint; failures and counterexamples retained.
- [2026-10-26 OTP 25 installer failure and supported CI runner pin](phase-b/2026-10-26-m1-ci-runner.md) — earlier run preserved; all six native OTP/mode lanes remain mandatory.
- [2026-10-26 actual-merge Port cleanup race and repair](phase-b/2026-10-26-m1-port-cleanup.md) — original failure retained; 14 current recovery cases per mode, including one new cleanup regression.

These records cover the bounded development profile, not a general actor
scheduler or production release.

## M2 design inputs

- [2026-10-27 ownership/task API inspection](phase-a/2026-10-27-m2-design.md) — proposed ADR/work plan and unchanged-code baseline, not M2 implementation evidence.

## Compiler migration

- [2026-10-26 all-branch verification and delivery ledger](phase-a/2026-10-26-zig-0.17-rollout.md) — historical 14/14 profile verification; branch handover and subsequent M1 acceptance are recorded separately.
- [2026-10-25 Zig 0.17 probe and initial inventory](phase-a/2026-10-25-zig-0.17.md) — historical failed pre-migration probe, not an acceptance record.

## Allocator research

- [2026-09-26 allocator source and binary audit](phase-a/2026-09-26-allocator-source-audit.md) — baseline selection/linkage and pinned snmalloc source findings, not snmalloc integration or performance evidence.
- [Evaluation plan](../snmalloc-evaluation.md) — proposed experiment and promotion criteria.

## Branch consolidation

- [2026-10-26 execution and recovery record](phase-a/2026-10-26-branch-consolidation.md) — 28 to 11 branches; all nine research topics retained, compiler-only PR #2 merged, immutable recovery tags and local assets preserved.

## Phases

- `phase-a/` — local logic, type/API contract, and compile-fail evidence.
- `phase-b/` — integration, wire fixtures, and real OTP interoperability.
- `phase-c/` — concurrency, network failure, liveness, boundedness, and performance stress.

## Required record fields

Each record identifies the commit, date, environment, commands, expected result, actual result, and related requirement or ADR. Packet captures and raw benchmark files must be referenced without embedding credentials or Erlang cookies.

A design document cannot cite a planned test as completed evidence.
