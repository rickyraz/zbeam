# ADR 0006 acceptance — compiled stateless binary handlers

- **Date:** 2026-11-09 UTC.
- **Decision:** [ADR 0006](../../adr/0006-compiled-binary-handler.md) is accepted for the separate custom-handler profile. Its body is unchanged.
- **Master commit:** `7dc27072f5b38165d90994863a69ec49ab1511f2`.
- **Actual-master CI:** [42159211378](https://github.com/rickyraz/zbeam/actions/runs/42159211378) passed 12/12 jobs.

## Rollout gates

| ADR 0006 step | Evidence |
|---|---|
| 1. Contract and rollback boundaries | [Design record](../phase-a/2026-11-05-compiled-handler-plan.md); PR #51 |
| 2. Local callback and inline length accounting | [Local lifecycle](2026-11-05-handler-local.md); PR #52 |
| 3. Mode routing and bounded binary encoding | [Wire primitives and OTP-generated vectors](../phase-b/2026-11-05-handler-wire-primitives.md), [service composition](../phase-b/2026-11-05-handler-composition.md); PRs #53 and #54 |
| 4. Separate executable, Elixir client and live faults | [Example](2026-11-05-handler-example.md), [OTP 25/26/27 interop and faults](2026-11-05-handler-interop.md), [real panic](2026-11-05-handler-panic.md); PRs #55, #56 and #60 |
| 5. Full suites and actual merged-master CI | CI run 42159211378 below; earlier per-PR master runs are recorded in each linked file |

In run 42159211378, each of the six OTP 25/26/27 debug/safe wire jobs reported
`PASS custom binary call reconnect handler-failure sibling stop` and the
per-target custom-profile marker. Each of the five Elixir/recovery jobs reported
the compiled uppercase example, the real compiled-handler panic case, the 4-case
custom fault suite, the 15-case owner suite and the 6-case process/oracle suite.
The retained actual-master failure
[42103993219](https://github.com/rickyraz/zbeam/actions/runs/42103993219) and its
[test-oracle repair](2026-11-05-restart-oracle.md) remain part of the record.

## Accepted scope and limits

Acceptance covers the contract that ADR 0006 states: one build-time stateless
function, copied input of at most 1 MiB, a zeroed 32-byte inline output, a
separate `call` command and unchanged SHA-256 profiles. It does not cover:

- a supervised Elixir owner for `call` (the raw client is an example only);
- outputs above 32 bytes, stateful handlers, destructors or dynamic plugins;
- in-process isolation between actors, OS-OOM or memory-corruption behavior;
- TLS, non-argv secret delivery, native-host soak or production readiness;
- exactly-once execution. Uncertain work is still not replayed.

Any change to these limits requires a new ADR rather than an edit to ADR 0006.

**Rollback:** restore the ADR 0006 status line and the status documents to
"proposed"; no code changes are associated with this record.
