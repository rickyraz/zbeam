# Local M2a accepted — 2026-10-27

**Accepted runtime tree: master `221a48d02e6f45df00284048f15f5c7240f545fb`.**
[Actual-master CI 40468839059](https://github.com/rickyraz/zbeam/actions/runs/40468839059)
passed **9/9 jobs**. Each job log identifies that checkout. This accepts local
T0–T4 ownership/lifecycle only, not M2b multi-actor OTP routing or production use.

## Delivered contract

- Two fixed, non-reused SHA-256 actor slots, copied distinct names (1–64 bytes),
  per-slot `Io.concurrent` Futures and no publication before both starts succeed.
- Copied inputs up to 1 MiB; four logical queue positions, one active consumer
  and five outstanding tickets per actor. Ten inline terminal records bound
  uncollected results; payloads total at most 10 MiB, excluding task/provider,
  metadata and caller-owned storage. No capacity-waiting sender task is created.
- Send/stop serialization; exactly one terminal result on controlled paths per
  accepted request, including canceled/dequeued/discarded work. This is local
  conservation, not exactly-once execution or recovery after process loss.
- Stop both admissions before joining either; preserve exit outcomes, join all
  started tasks, drain queued payloads and refuse premature deinit. External API
  users still require caller-owned joins before runtime destruction.
- Cooperative cancellation only. Noncooperative spin stalls actual join and is
  terminated/reaped externally. Panic/corruption remains a whole-process fault.
- Additive `TaskRuntime`; existing caller-owned `Runtime(T)`, all M1 network
  services, monitor flags, protocol/ETF/transport, fixtures and owner code remain
  unchanged from accepted M1. ADR 0001 dependency boundaries remain intact.

## Review and actual execution

| Unit | PR / candidate | Changed text lines |
|---|---|---:|
| Owner-approved design | #6 / `c064d8d` | 353 |
| Nonblocking mailbox | #7 / `0a72f17` | 81 |
| Internal ownership ledger | #8 / `18c905d` | 187 |
| Basic safe task owner | #9 / `072dfb6` | 390 |
| Deterministic lifecycle/conservation | #10 / `c92b04e` | 306 |
| Noncooperative subprocess watchdog | #11 / `96063ee` | 132 |
| Public API/production example | #12 / `0a1c229` | 187 |

Every implementation candidate and PR passed 9/9 jobs before normal merge;
actual-master runs after each unit also passed. No size exception, force push,
rebase or research promotion was used. Final PR #12 push **40468153697** and
PR **40468158965** passed 9/9 each. Its tested synthetic merge is recorded in
`pr12-checked.json.gz`; its tree equals the candidate and accepted master.
The core/owner PR logs identify that checkout and exercise all required profiles.

Linux x86-64 WSL2, Zig 0.17.0; local owner Elixir 1.20.4/OTP 29:

- [Basic owner](2026-10-27-m2a-task-owner.md): 100 fresh launches per mode,
  including real first/second concurrency failure and exact cleanup.
- [Deterministic lifetimes](2026-10-27-m2a-lifecycle.md): 100 fresh launches per
  mode, 2,800 checks including 1,400 new scenarios and 20,000 exact sibling jobs.
- [Watchdog](2026-10-27-m2a-shutdown-watchdog.md): 20 additional expected stalled
  joins followed by owned child kill/reap; conditional unit skips are disclosed,
  not counted as passing that separately executed process-boundary check.
- [Public API/integrated candidate](2026-10-27-m2a-public-api.md): 102,600 actor-A
  attempts plus 200 exact sibling jobs; exact accepted/terminal ID sets after
  eight external senders join. Production-mode example passes both modes.
- Local core/labs/lifecycle 69/69 steps each mode, with executed/cached/skipped
  counts preserved in raw records; pinned OTP 25/26/27 7/7 steps and zero missing
  targets each mode. Existing owner 4/4 steps, all 14 complementary cases per mode.
- Actual-master logs independently prove both new lifecycle/watchdog/example
  modes, all six native OTP lanes and both complete M1 recovery campaigns.

Installed compiler SHA-256:
`7c61539af19fa4082c94848f1c2b57b89e76dc6cfd5bd4c57764c3caf8f82272`.
Installed `lib/std/Io.zig` SHA-256:
`382a4e343017183eff88e311f983066f88306e7bfcd85a890723b3697f4b2732`.
These identify installed inputs, not independent upstream signature verification.

## Guardian-oracle follow-up before documentation closure

Initial closure head `d93a9a5` passed push 40470011719 but PR 40470016562
failed 8/9 at the existing guardian kill test's final procfs re-probe. Both
outcomes and the raw failure remain in the [oracle record](2026-10-27-guardian-terminal-state.md).
PR #14 (`f21c076`, 108 changed lines) corrects terminal-state parsing and removes
redundant post-terminal probes without changing production code or the deadline.
The old-oracle controlled counterexample is proven; original runner snapshots
are unavailable, so no unique historical X-state cause is asserted.

Repair push **40471116630**, PR **40471125388** and actual merge
**`885c930a7124f4d553b4554f9344617ddbd288e0`**, run **40471678530**, each
passed **9/9**. All actual-master job checkouts and both full owner campaigns
were checked. One hundred local guardian launches cover 400 real process
boundaries. M2a/M1 production code remains identical to `221a48d`; only the
verification oracle and notes change. Ordinary master-into-closure merge
preserves published history and the failed original candidate; no rerun erased it.

## Preservation, rollback and remaining work

All nine research refs and the retained M1 ref are unchanged. Original **399
asset hashes** and **28 immutable archive snapshots** were reverified; no checkout
from the research set was repurposed or any worktree removed. New implementation/review branches are
additive, not a new branch-count quota. Accepted ADR 0001–0003 bodies are unchanged;
ADR 0004 changes only its allowed status since design acceptance.

Rollback of M2a removes its additive owner/export/ledger, nonblocking method,
example and tests/build wiring; M1 code remains independently usable. Individual
work-unit records define narrower rollback boundaries. The documentation closure
contains no runtime/test/build/workflow change from the accepted guardian-repair
boundary `885c930`; its additive M2a production tree remains `221a48d`.

M2b still requires its own wire-profile ADR, atomic shared-route reservations,
output/monitor capacity and connection-epoch teardown proof. No generic handlers,
spawn/replacement, supervision tree, preemption, GC, zero-copy, allocator adoption,
ASan/TSan guarantee, native-host soak, OS-OOM/corruption proof, performance winner
or production certification is established. Package remains 0.0.1 pre-alpha.
