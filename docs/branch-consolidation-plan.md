# Reduce duplicate branches without retiring active research

**Status:** retention policy revised; per-branch execution approval pending.
**Inspected:** 2026-10-26 UTC. No archive, merge, branch deletion or worktree
removal is performed by this planning change.

Keep `master`, the M1 integration branch and **one working branch per active
research topic**. An unconfirmed topic is protected as active, not presumed
finished. Reduce source/migration duplication first; branch count is not a quota.

For the nine identified research topics, the provisional target is **11 branches**
while M1 is open: master + M1 + nine research branches. After accepted M1 integration
it becomes ten. More generally, with `R` active or unconfirmed research topics,
the target is `2 + R` before M1 acceptance and `1 + R` afterward. These estimates
apply only after safe pair consolidation and owner approval. Additional ongoing
work stays protected; the current 28 names may remain until handovers complete.

This replaces the earlier 28 → 2 → 1 proposal and updates only retention policy
in the [compiler rollout plan](zig-0.17-migration.md). It does not change the
[development roadmap](development-plan.md) or authorize feature promotion.

## Classification and default action

| State | Action |
|---|---|
| Active research or feature work | Keep a working branch and its required worktree |
| Unconfirmed status or owner | Keep; do not treat inactivity, an old commit or completed tests as retirement approval |
| Source plus compiler-migration branch for one topic | Select one working tip only after ancestry, current checks and owner handover; preserve both histories |
| Fully integrated work with no continuation | Retire only after recovery verification and owner release |
| Explicitly completed, parked or rejected research | Archive the exact tips and local assets, then retire only with explicit approval |

A tag preserves committed history, not uncommitted edits, ignored benchmark
samples, configuration or notes. No clean status, successful compiler migration
or negative performance result alone makes a research branch disposable.

## Protected research register

Every topic below is **unconfirmed and protected** until its owner chooses active,
completed, parked or rejected. Original names have prefix `explore/`; migration
counterparts have prefix `migrate/zig-0.17-`. No topic is selected for retirement.

| Topic | Observed source worktree | Current disposition |
|---|---|---|
| `zigler-baseline` | Main repository | Keep; pair consolidation requires owner handover |
| `batched-requests` | Attached sibling | Keep; pair consolidation requires owner handover |
| `beam-backpressure` | Attached sibling | Keep; pair consolidation requires owner handover |
| `io-overhead` | Attached sibling | Keep; pair consolidation requires owner handover |
| `worker-recovery` | Attached sibling | Keep; preserve this experiment separately from M1 recovery |
| `actor-admission` | Attached sibling | Keep; pair consolidation requires owner handover |
| `allocator-baselines` | No attached source worktree | Keep; lack of a worktree is not retirement evidence |
| `request-arena` | No attached source worktree | Keep; pair consolidation requires owner confirmation |
| `snmalloc` | No attached source worktree | Keep; non-default adoption does not end research |

The existing research progress record on the research branches retains experiments
and lists open gates. Measurements and migration smoke results do not establish
that all investigation is finished. Keep different topics separate, not merged
into one unrelated research branch or into master merely to reduce names.

## Verified integration facts

- Remote has 14 source heads and 14 migration candidates, with nine original
  worktrees plus the session-owned migration worktree. The [migration ledger](evidence/phase-a/2026-10-26-zig-0.17-rollout.md)
  preserves their earlier full-SHA snapshot; refresh before any operation.
- Remote master is `497d346`; local/cached `11c3319` is stale. Compiler candidate
  `a0464e6` has [successful CI](https://github.com/rickyraz/zbeam/actions/runs/40275692277).
- M1 `c4b53e1` has [successful CI run 40282597708](https://github.com/rickyraz/zbeam/actions/runs/40282597708).
  Earlier `64f6388` [failed OTP 27 safe registration](https://github.com/rickyraz/zbeam/actions/runs/40279020842)
  with `ConnectionRefused`. The later green documentation-only run does not prove
  a root cause or corrective fix. Retain that failure for acceptance triage.
- Accepted labs are ancestors of master; original lifecycle/planning tips are
  ancestors of M1. Migration tips can still differ: `a0464e6` and `88a5786` are
  not ancestors of the inspected M1 tip. Similar contents are not a fast-forward.
- Master was unprotected at inspection. PR/check enforcement is proposed, not
  assumed. CI and ownership must be refreshed for each actual selected tip.

## Execution order and stop gates

### 1. Inventory owners and protect recoverable work

Refresh heads, PRs, CI and every attached worktree. Record each source/candidate
pair, exact tips, owner, status, intended working branch and protected assets.
Keep unknowns unchanged. Obtain an explicit decision before marking a topic
inactive or a branch obsolete; an attached worktree blocks uncoordinated changes.

Preserve existing `archive/zig-0.16/<source>` tags. Before any ref retirement,
publish annotated 0.17 recovery tags for the exact candidate snapshots and verify
remote tag objects and peeled SHAs. If a source advanced past its frozen tag,
preserve that new tip too. Never move an existing archive tag; use a new name.
Back up and hash ignored/untracked assets outside any worktree before a switch or
removal. Record observed CI honestly, including unknown or failed status.

### 2. Consolidate one source/migration pair at a time

Prefer keeping the familiar `explore/<topic>` name at its approved 0.17 tip,
without creating another branch. This is a proposed name choice, not an operation
behind an owner's checkout. The owner may retain the migration name instead.

For each pair, require current branch-specific compiler, contract and external
checks, a clean/consented handover, both exact recovery tips, and a valid ancestry
check. Fast-forward the retained branch only when valid and coordinated. If the
source advanced independently, stop, reconcile its changes and reverify; never
reset or force-push it to the migration snapshot. Do not reuse old compiler objects
or alter global compiler configuration during handover.

Retire the redundant name only after its commits are reachable from the retained
branch or verified recovery tags and its owner releases it. No wildcard deletion
or fixed 26-name list is authorized. If Git refuses deletion, stop for review.
**Exit:** one approved working branch per consolidated topic; no research lost.

### 3. Integrate completed shared work without sweeping up experiments

Review the compiler-only candidate against refreshed master with current-SHA
core/labs/negative-fixture, argument and native OTP 25/26/27 checks. Preserve
published history through a reviewed merge. Do not promote NIFs, arenas, snmalloc
or independent research behavior with it.

After coverage and owner release are confirmed, lab/planning/foundation aliases
may be retired. Confirm that no new work continues there first; if uncertain,
keep the branch. Do not merge superseded documents just to obtain merged status.

### 4. Review M1 and close only that workstream

Triage the earlier OTP 27 registration failure without assuming it is flaky or
weakening checks. Merge refreshed master into M1 normally when fast-forward is
not valid, preserving the bounded monitor and no-replay owner contracts. Review
existing W0–W5 work units separately; use cohesive sequential slices or an explicit
`size:exception` above the 400-line review budget, not shortened tests/evidence.

Require current merge-result core/labs debug/safe, native OTP 25/26/27 in both
modes, guardian and all 13 complementary recovery cases per mode, including
required GitHub lanes. Merge only after approval. Retire the M1 branch only after
accepted integration and owner release, or a separate explicit shelving decision.
Research branches remain; completing M1 is not approval to archive them.

## Worktree and ongoing policy

Keep worktrees needed by active or unconfirmed work, even if this leaves more
than two. Consolidating a pair does not authorize removing its worktree or cache.
The main worktree need not switch to master while its research owner needs it.
Do not clean ignored files, force-remove worktrees or alter another session's refs.

Keep master plus branches for actual ongoing topics. Do not impose an arbitrary
one-feature limit across independent research. Finished branches may be retired;
paused branches require an explicit archive decision. Require reviewed PRs and
green checks for master, and enable protection when approved. Resume an archived
topic from its exact tag only for a named task; port/retest against current master.

## Approval checklist

- [ ] Confirm topic owners and statuses; unknowns remain protected.
- [ ] Approve a retained name/tip for each source/migration pair independently.
- [ ] Verify exact recovery tags and backups of ignored/uncommitted assets.
- [ ] Confirm ancestry, current checks and worktree handover before pair changes.
- [ ] Retire only individually approved redundant or explicitly inactive refs.
- [ ] Review compiler/M1 integration separately from research retention.

This change revises documentation only. No branch is merged, renamed, promoted
or deleted; no worktree, tag, runtime code or protection setting is changed.
No workflow rerun is requested.
