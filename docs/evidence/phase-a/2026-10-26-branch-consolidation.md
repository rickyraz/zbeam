# Branch consolidation execution — 2026-10-26

## Outcome and authorization

The repository owner explicitly authorized local execution, commits and push,
not another planning-only iteration. Consolidation reduced **28 remote branches
to 11**, with the same 11 local names and configured upstreams. All nine research
topics remain protected; none was classified finished or merged into master.

The host process/worktree inspection found only the current Pi session, nine
unchanged clean original worktrees and the clean migration checkout. Source tips
matched their frozen 0.16 archives. No other live Pi checkout was switched.

## Retained work

| Working branch | Verified migration snapshot |
|---|---|
| `master` | `a0464e6`, merged as `dc06c64` through PR #2 |
| `feat/monitorable-worker` | `f07df4d`; M1 remains unmerged into master |
| `explore/zigler-baseline` | `83d5a12` |
| `explore/batched-requests` | `ad9df2f` |
| `explore/beam-backpressure` | `89cb7fd` |
| `explore/io-overhead` | `667a00f` |
| `explore/worker-recovery` | `c6e21c1`; distinct from M1 recovery |
| `explore/actor-admission` | `b3d1299`, followed by test-accounting fix `b1dff6c` |
| `explore/allocator-baselines` | `3d4a541` |
| `explore/request-arena` | `0faf241` |
| `explore/snmalloc` | `889a563` |

These are code/handover snapshots, before documentation-only recording commits.
The [machine-readable disposition](2026-10-26-branch-consolidation.json) retains
full SHAs and the exact retired names; current heads may advance normally.

## Operations performed

1. Inventoried exact remote/local tips, ancestries, dirty state and ignored files.
   All 14 migration tips had observed successful GitHub CI before handover.
2. Published **14 annotated `archive/zig-0.17/<source>` tags**, atomically; checked
   both remote tag objects and peeled commit SHAs. Existing 0.16 tags were kept.
3. Backed up 399 ignored evidence/asset files outside every worktree, verified
   archive contents against SHA-256, and retained build/dependency caches in place.
   Preflight found zero target-tree/ignored-file collisions. The private backup
   is `zbeam-research/backups/branch-consolidation-2026-10-26/`; tags alone do not
   preserve ignored data. Asset hashes were checked again after handover.
4. Inspected the compiler-only diff: 24 files, 129 additions/22 removals. Created
   [PR #2](https://github.com/rickyraz/zbeam/pull/2), waited for its checks, then
   merged normally without squashing published history. The merge introduces
   compiler adaptation and accepted labs, not M1 or research behavior.
5. Fast-forwarded the ten retained source research/M1 branches, atomically pushed
   them, and configured upstreams. The three previously remote-only allocator
   research names now also exist locally. No reset or force-push was used.
6. Detached the completed lab/planning worktrees at their exact historical 0.16
   archive checkpoints. Their files/caches remain; no worktree was removed. The
   session migration checkout now tracks actual master, replacing stale `11c3319`.
7. Deleted all 14 `migrate/zig-0.17-*` aliases plus `explore/lab-contracts`,
   `docs/worker-lifecycle-plan` and `feat/worker-lifecycle`. Local deletion used
   ordinary `git branch -d`; remote deletions were one explicit atomic update.
   Their history remains reachable through verified archives and retained work.
8. Pruned stale tracking refs and verified exactly 11 matching local/remote heads,
   configured upstreams, ten clean worktrees and unchanged ignored assets.

## Verification and discovered follow-up

Linux x86-64 WSL2, Zig 0.17.0, `.zig-cache/0.17`; no global compiler change.

- Compiler PR checks passed: run [40285599874](https://github.com/rickyraz/zbeam/actions/runs/40285599874).
  Actual master merge CI passed: [40286267383](https://github.com/rickyraz/zbeam/actions/runs/40286267383).
- Actual master `zig build test-all test-labs -j2 --summary all`, debug and safe:
  **63/63 steps and 65/65 newly executed tests per mode**; cached cases remain
  distinguishable in the raw summaries. Formatting and argument smoke passed.
- Post-promotion actor-admission CI exposed an unsupported close/drain scheduling
  assumption: expected five deliveries, observed six. Commit `b1dff6c` conserves
  exactly the successful/failed in-flight send and additionally rejects new sends
  after termination. Runtime sources/ADR are unchanged. Its branch contains the
  dedicated failure record, 200 isolated launches/400 cases and both-mode
  core/labs 63/63-step, 78/78-test evidence. New push CI runs normally.
- Latest inspected M1 handover CI [40287149686](https://github.com/rickyraz/zbeam/actions/runs/40287149686)
  passed. Earlier `64f6388` OTP 27 registration `ConnectionRefused` remains retained
  and undiagnosed; no claim of a corrective native fix is made.

This record does not declare M1 accepted, experimental allocators adopted,
threaded NIF teardown safe, or a new performance/production result. Current
post-push workflow status is separate from the immutable handover snapshots.
