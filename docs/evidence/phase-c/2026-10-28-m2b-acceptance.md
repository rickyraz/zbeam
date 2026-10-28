# M2b acceptance — 2026-10-28

## Accepted boundary

The bounded two-worker development profile on implementation master
`14ddc5d26f6fd73425937f5ecb731f256db56520` implements [ADR 0005](../../adr/0005-two-worker-wire-profile.md).
It provides a separate `serve-workers` listener and `zbeam_workers` discovery,
two distinct stable PIDs for one service lifetime, one authenticated peer at a
time, correlated SHA-256 and independent stop, PID/name monitors, conservative
pre-read capacity reservations, and joined old-epoch discard without replay.
[Usage and exact limits](../../two-worker-wire.md). M1 and caller-owned local
`Runtime(T)` retain their separate contracts. Package version remains 0.0.1
pre-alpha; this is neither general OTP compatibility nor production certification.

## Integrated verification

Linux x86-64/WSL kernel 6.18.33.2, Zig 0.17.0 (executable SHA-256
`7c61539af19fa4082c94848f1c2b57b89e76dc6cfd5bd4c57764c3caf8f82272`),
Elixir 1.20.4 / OTP 29 for owner tests; `debug` and `safe`, unless specified:

| Gate | Evidence and scope |
|---|---|
| Actual implementation master | [CI 40655977846](https://github.com/rickyraz/zbeam/actions/runs/40655977846), 9/9 jobs, with six mandatory native OTP 25/26/27/mode lanes and two recovery lanes. Each OTP job includes the M2b profile marker; recovery lanes include the M1 and M2b tests. |
| Core, labs, lifecycle, recovery | `zig build test-all test-labs test-task-lifecycle test-worker-recovery -Doptimize=<mode> -j2 --summary all`: 73/73 steps each. Debug executed 141/143 Zig checks and safe 168/170, with two conditional skips each; other steps were cached. Explicit spin watchdog and local runtime example passed; M1 13 ordinary and one private-EPMD case per mode; the M2b suite executed two cases in each normal and private-EPMD run per mode. |
| Independent protocol vectors | [Thirteen OTP-generated frames](../phase-b/2026-10-28-m2b-vectors.md); OTP 25/26/27 generated identical bytes, with conformance checks in both modes. These are bounded synthetic frames, not a proof of every OTP encoding. |
| OTP interoperability | `zig build test-interop-docker -Doptimize=<mode> -j2 --summary all`: seven steps, three required OTP releases and zero missing per mode. Both M1 and M2b run; M2b checks distinct PIDs, exact digests through 1 MiB, 40 correlated requests, disconnect/reconnect, 64 monitor slots and independent stop. |
| EPMD loss | The [actual CLI](2026-10-28-m2b-production-epmd.md) is tested against an owned daemon inside isolated OTP 25/26/27 containers in both modes; node-down/monitor and fail-stop are checked, not automatic re-registration. |
| Connection faults/epoch | [Launch, read, decoder, writer and cancellation faults](../phase-a/2026-10-28-m2b-connection-faults.md), plus a [deterministic disconnect barrier](2026-10-28-m2b-epoch-barrier.md). Reader/collector joins precede release, and a paused accepted job blocks return until drained. |
| External recovery | [Guarded process-loss campaign](2026-10-28-m2b-process-recovery.md) checks external replacement and no replay; a request sent while the child is SIGSTOPped is uncertain, not proven accepted. Twenty fresh campaigns per mode and their procfs-oracle failure/correction are retained. |
| Monitor/output ordering | [Focused control campaign](2026-10-28-m2b-control-ordering.md) checks 64 exits while sibling work is paused and failed-write cleanup. One writer emits control frames sequentially; no unbounded output queue is introduced. |

Raw final core/OTP logs are archived next to this record. The separate
[connection fault record](../phase-a/2026-10-28-m2b-connection-faults.md) retains
the timeout-versus-cancellation repair and failed attempts. The separate
[error policy record](../phase-a/2026-10-28-m2b-error-policy.md) records the M1
regression introduced during integration and its repair. Earlier successful
existing-profile jobs are not relabeled as M2b compatibility evidence.

## Boundaries and preservation

Four queue positions and five outstanding tickets per actor, ten output items,
64 monitor slots and fixed 16 KiB encoding scratch are logical bounds, not a
process-RSS or performance guarantee. Tick reads may be blocked by saturation;
stop, cancel and drainage are cooperative. Noncooperative CPU work requires an
external kill/reap, while panic/corruption affects the whole native process.
M2b recovery tests orchestrate replacement externally; no reusable M2b supervisor,
automatic replay, exactly-once guarantee, TLS, arbitrary actors or scheduler is
provided. Cookie-in-argv, deployment secrets, native-host soak, OS-OOM/corruption,
sanitizers and BEAM sender-backpressure measurement remain open.

A preservation audit checked 399 ignored source assets against both original
paths and backup archives, nine research refs plus the M1 ref locally/remotely,
and 28 annotated tag objects against the remote with their original peeled
commits. All 13 worktrees were observed, with only the active documentation
worktree dirty during this audit. The older temporary `/tmp/zbeam-m2b-20261027` ledger is unavailable;
committed unit evidence and the newer private ledger remain, and missing raw
files are not represented as recovered.

This acceptance record summarizes the integrated profile; historical unit
records retain their original source revisions, failures, skips and cached-step
counts. A documentation-only closure does not make a new runtime claim.
