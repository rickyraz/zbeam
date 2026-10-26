# Branch retention and completed consolidation

**Status: executed locally and on GitHub, 2026-10-26.** The repository owner's
explicit execution instruction authorized the handover after validation; this
is no longer an approval-pending plan. **28 remote names became 11**, with the
same 11 local branches and synchronized upstreams. All nine research topics stay
protected as active or unconfirmed. M1 was later accepted into master through
PR #3 and repair PR #4; its branch/checkout remains retained, not auto-deleted.

The [execution/recovery record](evidence/phase-a/2026-10-26-branch-consolidation.md)
contains exact snapshots, operations, checks and exclusions. The compiler-only
[PR #2](https://github.com/rickyraz/zbeam/pull/2) imported no M1 or experimental
feature to reduce branch count. [Later M1 acceptance](evidence/phase-b/2026-10-26-m1-integration.md)
was separately authorized and verified; all nine research topics stay independent.

## Retained working branches

- `master`: accepted Zig 0.17 compiler baseline, labs and bounded M1 profile.
- `feat/monitorable-worker`: retained M1 integration/documentation checkout;
  branch retirement remains a separate coordinated operation.

| Protected research branch | Disposition |
|---|---|
| `explore/zigler-baseline` | Keep its tested 0.17 baseline and eligible-NIF limits |
| `explore/batched-requests` | Keep; no general performance winner declared |
| `explore/beam-backpressure` | Keep its demand/pause contract |
| `explore/io-overhead` | Keep its independent profiler/ownership experiment |
| `explore/worker-recovery` | Keep separately from the M1 owner |
| `explore/actor-admission` | Keep; close/drain test accounting follow-up preserved |
| `explore/allocator-baselines` | Keep all declared comparator controls |
| `explore/request-arena` | Keep separately from the allocator/sn allocator siblings |
| `explore/snmalloc` | Keep pinned optional ABI work; no default adoption |

Each retained source name now points to its verified 0.17 history rather than
maintaining duplicate source/migration names. Missing worktrees do not imply
inactive research; the three allocator research names also exist locally.

## Completed protection and cleanup

- All 14 candidate tips were published as annotated `archive/zig-0.17/<source>`
  tags before retirement, with remote tag object and peeled-SHA verification.
  Existing `archive/zig-0.16/<source>` checkpoints remain immutable.
- All original sources were unchanged/clean at preflight, and host inspection
  found only this Pi session. Updates were explicit, owner-authorized ordinary
  fast-forwards, not switches behind another live session or force resets.
- 399 ignored evidence/assets were independently backed up and hash-verified.
  Build/dependency caches and all ten worktrees remain. Tags are not backups of
  uncommitted or ignored files.
- All 14 `migrate/zig-0.17-*` names and the completed lab/planning/foundation
  aliases were retired locally/remotely after recovery checks. Their exact tips
  remain archived; no wildcard cleanup or force deletion was used.
- The completed lab/planning worktrees are detached at their historical archive
  checkpoints, not removed. The session migration checkout now uses real master.

## Continuing policy

Keep master plus a working branch for every ongoing research or feature topic.
**Unknown status remains protected**; age, old commits, a negative result or a
completed migration test never proves a research topic finished. The current 11
names are an outcome, not a quota. New independent work may require more branches.

Reduce duplicate names only after ancestry, current branch-specific checks,
exact recovery snapshots and a coordinated handover. If a source advances
independently, reconcile and reverify; never reset or force-push to a migration
snapshot. Do not change global compiler configuration or reuse old compiler
objects. Keep names familiar where safe rather than introducing another alias.

Retire a research topic only when explicitly completed, rejected or parked.
Preserve ignored/uncommitted assets separately and release any live worktree
owner first. Do not force-remove worktrees or clean another session's files.
Resume archived work from its exact tag for a named task and port/retest against
current master; do not recreate all migration branches automatically.

## Separate M1 acceptance — 2026-10-26

M1 completed its own review and current merge-result acceptance, rather than
merging merely to reach ten branches. The owner explicitly approved the
preserved-history size exception; original W0–W5 units and evidence remain.

Earlier M1 `64f6388` failed OTP 27 safe registration with `ConnectionRefused`.
Later handover runs passed, including `f07df4d` on the retained feature name;
[acceptance triage](evidence/phase-b/2026-10-26-m1-acceptance.md) now reproduces
and prevents the EPMD launcher readiness race without claiming the old runner's
exact trace. Master is integrated by ordinary merge `664fc81`; current local
core/labs debug/safe, native OTP 25/26/27 in both modes, guardian and all 13
original recovery cases per mode passed. PR #3 merged normally; actual-merge
CI exposed a Port cleanup race, repaired in PR #4. Repaired master `88db721`
passed all nine CI jobs, including 14 current recovery cases per mode.
[Acceptance](m1-review.md) closes M1, not any research topic.

Research promotion, production readiness, threaded-NIF safety and performance
claims remain independent decisions. Branch protection was not changed;
M1-to-master integration occurred separately from branch consolidation.
