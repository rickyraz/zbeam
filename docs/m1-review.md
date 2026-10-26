# Bounded M1 review and acceptance

**Status: accepted into master, 2026-10-26.** Explicit owner `size:exception`
approval authorized normal PR #3 integration; PR #4 repaired the subsequent
cleanup race. Actual repaired-master CI passed 9/9 jobs. The
[acceptance record](evidence/phase-b/2026-10-26-m1-integration.md) preserves the
sequence and failures. Acceptance covers the bounded development profile,
not M2 or production release.

## Integration boundary

Master `3919341` is an ancestor after ordinary merge `664fc81`; that merge changed
no tree bytes. Commit `e3cf4d2` fixes launcher readiness, not native retry or wire
semantics. Commit `5f20b7f` [pins a supported interop runner](evidence/phase-b/2026-10-26-m1-ci-runner.md)
after both OTP 25 installer lanes failed before tests; no required lane is waived. The current development profile has one synchronous SHA-256 worker,
one active peer, stable PID across reconnects, correlated requests, PID/named
monitoring and externally supervised no-replay recovery. It does not add task-owning
spawn, links, a native supervision tree, general ETF/OTP compatibility or GC.

Nine research branches remain independent. Their retained historical evidence is
not a feature merge or an allocator/performance promotion. Package version stays
0.0.1 pre-alpha; the v0.5 draft is not a release inventory.

## One slicing pass and exception request

At `e3cf4d2`, the master-to-candidate diff has **392 files and 25,722 changed text
lines**, including **20,020 unchanged historical raw-sample lines in 20 files**.
The final approved PR #3 contained 396 files and 25,859 changed text lines. Raw data, tests, comments and provenance are not removed
or compressed to manufacture a smaller review. Existing gzip evidence retains
its established storage format.

The published work units provide the review slices below. Several cohesive units
still exceed 400 lines even without a giant combined PR; splitting data rows or
separating a safety change from its tests/evidence is not an honest solution.
The owner **explicitly approved `size:exception`** before PR #3 merged normally
as `2241e7f`. Cleanup repair PR #4 was 106 changed text lines and merged normally
as `88db721`. No force/squash/rebase or deletion of evidence was used.

| Review slice | Published boundary | Original added + removed lines |
|---|---|---:|
| Handshake deadlines | `7b812d3` | 310 |
| Frame/write/EPMD lifetime | `c47968d` | 279 |
| SHA-256 foundation and retained measurements | `38caeb4` | 20,495 |
| W1 lifecycle ADR | `04d6d2b` | 100 |
| W2 references/pure monitor controls | `27ba7d1` | 325 |
| W3 worker identity/routing | `99928a0` | 459 |
| W4 PID/named monitoring | `50b315b` | 550 |
| W5 Linux guardian | `5502b2c` | 135 |
| W5 procfs disappearance checks | `ca3fe1b` | 122 |
| W5 external owner and failure campaign | `b43f5df` | 1,142 |

These are source work-unit boundaries, not a claim that each is an independently
current-master-compatible PR. Follow the retained history and actual final diff.
ADR 0003 supersedes ADR 0002's PID-only capability decision; accepted ADR bodies
remain unchanged. Review compiler migration and archival reports as provenance,
not as additional runtime behavior.

## Review and acceptance gates

1. Check the battery DAG: pure references/control parsing stay in ETF/protocol;
   transport never imports actor/runtime; the umbrella remains behavior-free.
2. Check service/peer/frame ownership and bounds: 1 MiB hash input, 2 MiB packet,
   4 MiB decoded budget, 64 subscriptions/connection and cleanup before peer free.
3. Check stop/monitor/reconnect semantics, canonical owned reference IDs, stale
   PIDs, duplicate/demonitor behavior and the absence of hidden read-ahead/queues.
4. Check the Linux guardian and one-slot external owner: uncertain work fails,
   no replay, caller/owner/VM/native loss cleanup, bounded deadlines/restarts.
5. Require current core/labs debug/safe, native OTP 25/26/27 in both modes and
   guardian plus all 13 original recovery cases and the added cleanup regression
   per mode (14 current cases). External
   Elixir 1.20.4/OTP 29 evidence is distinct from the native wire matrix.
6. Review the EPMD readiness counterexample and forced-cleanup regressions. The
   race class is demonstrated; the old runner's exact trace was not captured.
7. Retain the [explicit owner approval](https://github.com/rickyraz/zbeam/pull/3#issuecomment-6419841418)
   and current CI evidence. This exception is specific to PR #3, not permission
   to bypass review budgets on future work.

M2 implementation, native-host/long-soak certification, alternate allocators,
zero-copy, transport security and production release gates remain out of scope.
