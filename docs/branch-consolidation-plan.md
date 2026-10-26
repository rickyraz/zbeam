# Consolidate 28 branches to one maintained baseline

**Status:** proposed; no archive, merge, branch deletion or worktree removal is
executed by this plan. **Inspected:** 2026-10-26 UTC.

**Target: 28 remote branches → 2 during M1 review → 1 after M1 acceptance.**
Keep `master` and the existing `migrate/zig-0.17-monitorable-worker` as the sole
active integration branch. Preserve inactive experiments as annotated tags,
not permanent branches or an unrelated combined research branch.

This changes the branch-retention sequence in the [compiler rollout plan](zig-0.17-migration.md),
not its verified compiler results or the [runtime roadmap](development-plan.md).
It does not authorize merging M1 or deleting another session's branch.

## Current facts and merge blockers

- GitHub has 14 original source branches and 14 migration candidates. Nine
  original worktrees plus the session-owned migration worktree remain attached.
- No open PR was found. Remote `master` is `497d346`; local/cached master
  `11c3319` is stale and must not be the integration base.
- Compiler candidate `a0464e6` has [successful CI run 40275692277](https://github.com/rickyraz/zbeam/actions/runs/40275692277).
- M1 `64f6388` has [failed CI run 40279020842](https://github.com/rickyraz/zbeam/actions/runs/40279020842):
  `otp-interop (27, safe)` reports `FAIL registration` and `ConnectionRefused`.
  Other jobs passed, but the run is not green. Earlier successful runs do not
  clear this failure. Root cause and a corrective change are not established.
- The source labs are ancestors of remote master. Original lifecycle and planning
  branches are ancestors of M1. However, compiler tip `a0464e6` and foundation
  migration tip `88a5786` are **not** ancestors of M1: shared content is not a
  fast-forward relationship. The compiler merge base is `ae7197d`.
- `master` is currently unprotected. A PR/check gate is proposed below, not
  assumed to be enforced by GitHub already.

The [14-source ledger](evidence/phase-a/2026-10-26-zig-0.17-rollout.md)
records exact source/candidate SHAs and evidence. Refresh it before execution;
this plan's snapshot is not permission to delete a subsequently advanced tip.

## Disposition: keep two, retire 26

| Branch group | Count | Disposition |
|---|---:|---|
| `master` | 1 | Keep; promote only the reviewed compiler candidate first |
| `migrate/zig-0.17-monitorable-worker` | 1 | Keep until M1 CI, review and integration complete |
| `migrate/zig-0.17-master`, `migrate/zig-0.17-lab-contracts` | 2 | Retire after compiler integration and tag verification; both currently point to `a0464e6` |
| `explore/lab-contracts` | 1 | Retire after owner release; its accepted source is already in master |
| `docs/worker-lifecycle-plan`, `feat/worker-lifecycle`, `feat/monitorable-worker` | 3 | Retire after owner release and confirming ancestry into the retained M1 branch; do not discard their newer migration-only records |
| `migrate/zig-0.17-docs-plan`, `migrate/zig-0.17-worker-lifecycle` | 2 | Archive then retire; do not merge solely to make Git report them as merged |
| Nine other `explore/*` research branches | 9 | Archive then retire; retain results without promoting experiments |
| Their nine migration counterparts | 9 | Archive their latest 0.17 source/evidence and retire |

The nine research topics are zigler-baseline, batched-requests, beam-backpressure,
io-overhead, worker-recovery, actor-admission, allocator-baselines, request-arena
and snmalloc. Archiving a topic is not declaring it merged, safe for production
or unsuitable for future investigation.

## Execution order

### 1. Freeze and publish recoverable 0.17 snapshots

1. Refresh remote heads, open PRs, worktree ownership, dirty/ignored files and CI.
   Stop on an unexpected new commit or active writer; reconcile with its owner.
2. Preserve the published `archive/zig-0.16/<source>` tags unchanged. They retain
   old baselines, **not** the complete compiler migration or its new evidence.
3. Create 14 annotated `archive/zig-0.17/<source>` tags at the latest corresponding
   migration tips from the ledger. No such remote tags existed at inspection.
   Tag messages identify source branch, exact candidate SHA and observed CI state.
4. Publish those exact tags and verify both remote tag objects and peeled SHAs.
   Record source → migration → archive → keep/retire in a retirement manifest.
   Never move an existing archive tag; an advanced snapshot needs a new tag name.

**Exit:** every branch scheduled for removal has a verified remote recovery ref,
including any commits added after `64f6388`. A failed-CI snapshot is labeled as
such; an archive is not a release or acceptance claim.

### 2. Land the compiler-only baseline

Open the canonical candidate's PR against refreshed remote `master`. Preserve
published history through a reviewed merge; do not silently replace master or
squash unrelated feature work. Require current-SHA core/labs/negative-fixture,
argument-forwarding and OTP 25/26/27 checks. Reverify if the base changes.

**Exit:** remote master contains the approved Zig 0.17 baseline and accepted labs,
without M1, optional NIFs, arenas, snmalloc or other research behavior.

### 3. Release worktrees and retire the 26 redundant names

- Coordinate with all owners first. Keep the main repository worktree and one M1
  worktree; do not check the same branch out in two worktrees.
- Move the main worktree to reviewed master only with its owner's cooperation;
  update stale local master through a normal fast-forward, never a reset.
- Before removing an extra worktree, inspect and preserve untracked **and ignored**
  files, private configuration, notes and artifacts. A clean `git status` alone
  is insufficient. Do not remove another session's worktree/cache or use force.
- Retire only the 26 explicit non-keep names above, in small batches. Immediately
  before each deletion, compare the live tip to the retirement manifest and
  confirm the published archive contains that exact tip.
- Remove local/remote branch refs normally after release. If Git refuses a local
  deletion, stop for owner review; do not bypass it with force. Never use a bulk
  name-matching deletion script, reset, force-push or tag rewrite.
- Recheck the two remaining remote heads and all archive refs after each batch.
  Source/candidate pairs need not both remain branches after their tips are saved.

**Exit:** only master and the M1 integration branch remain active. The original
migration audit expects 14 unchanged source heads; it must not be reused as the
post-retirement validator. Validate against the approved retirement manifest.

### 4. Close M1, then remove its temporary branch

1. Investigate the OTP 27 safe registration failure first, including EPMD readiness
   and owned test-process startup. Do not label it flaky, weaken assertions or
   rerun blindly until green. A behavior fix includes a regression and evidence.
2. Integrate refreshed master into the existing M1 branch with a normal merge;
   its current tip cannot simply fast-forward past `a0464e6`. Preserve M1's
   bounded PID/named-monitor and no-replay external-owner contracts.
3. Review existing W0–W5 work units separately from compiler work. Do not open 14
   migration PRs. If M1 exceeds the 400-line review budget, use sequential cohesive
   PR slices or request explicit `size:exception`; do not shorten tests/evidence.
   At most one extra review branch is temporary, then deleted after landing.
4. Require current merge-result core/labs debug/safe, native OTP 25/26/27 in both
   modes, guardian and all 13 complementary recovery cases per mode. Include all
   required GitHub lanes, not just an earlier successful SHA.
5. Merge only after approval. Archive the final integration tip if it advanced,
   verify its history is retained by master/recovery refs, and retire the M1
   branch/worktree after owner release.

**Exit:** one maintained remote branch, `master`. If M1 is not accepted, keep its
single active branch until an explicit archive-only decision; never merge a
feature merely to reduce the branch count.

## Steady-state policy and recovery

- Keep one long-lived `master`, with at most one ordinary short-lived work branch.
  Avoid permanent `develop`, parallel compiler branches and dormant research heads.
- Use a named temporary branch only for current work. Finished work is merged;
  parked/rejected work receives an archive tag and loses its active branch.
- Require reviewed PRs and green checks for master; enable branch protection when
  approved. Do not enable automatic deletion until the archive/owner gates hold.
- Resume archived research only for a named current task. Recover the exact tag
  into one short-lived branch, then port/retest against current master. Do not
  resurrect the entire old research branch set or relabel historical measurements.

## Approval checklist

- [ ] Approve the two-branch intermediate and one-branch final target.
- [ ] Verify/publish 0.17 archive tags and the exact 26-name retirement manifest.
- [ ] Approve and merge the compiler-only PR with current checks.
- [ ] Obtain worktree-owner release and confirm ignored-file preservation.
- [ ] Retire non-keep refs; verify recovery independently of stale tracking refs.
- [ ] Resolve M1's failed CI, approve its review boundary, and verify the merge result.
- [ ] Retire the final M1 branch only after accepted integration or explicit shelving.

No merge, deletion, workflow rerun, protection change or runtime fix is performed
by the planning change. Recovery and ownership checks precede convenience.
