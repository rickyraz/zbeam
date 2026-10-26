# Branch retention and completed consolidation

**Status: executed locally and on GitHub, 2026-10-26.** The repository owner's
explicit execution instruction authorized the handover after validation; this
is no longer an approval-pending plan. **28 remote names became 11**, with the
same 11 local branches and synchronized upstreams. All nine research topics stay
protected as active or unconfirmed. M1 remains a separate feature branch.

The [execution/recovery record](evidence/phase-a/2026-10-26-branch-consolidation.md)
contains exact snapshots, operations, checks and exclusions. The compiler-only
[PR #2](https://github.com/rickyraz/zbeam/pull/2) is merged; no M1 or experimental
research feature was imported into master to reduce branch count.

## Retained working branches

- `master`: accepted Zig 0.17 compiler baseline and labs.
- `feat/monitorable-worker`: existing W0–W5 development profile; not M1 acceptance.

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

## Remaining integration work, not cleanup blockers

M1 needs its own review and current merge-result acceptance. Completing branch
consolidation does not waive it or merge M1 just to reach ten branches. Preserve
W0–W5 review units, or request an explicit size exception for cohesive overages;
never shrink tests/evidence to meet a review budget.

Earlier M1 `64f6388` failed OTP 27 safe registration with `ConnectionRefused`.
Later handover runs passed, including `f07df4d` on the retained feature name;
[acceptance triage](evidence/phase-b/2026-10-26-m1-acceptance.md) now reproduces
and prevents the EPMD launcher readiness race without claiming the old runner's
exact trace. Master is integrated by ordinary merge `664fc81`; current local
core/labs debug/safe, native OTP 25/26/27 in both modes, guardian and all 13
complementary recovery cases per mode pass. [PR review/checks and an explicit
size exception](m1-review.md) still gate M1-to-master integration; no research
retirement follows from these results.

Research promotion, production readiness, threaded-NIF safety and performance
claims remain independent decisions. Branch protection changes and M1-to-master
integration were not performed as part of this cleanup.
