# Migrate master and every active branch to Zig 0.17

**Status: 14/14 profiles verified and archived; compiler PR #2 merged and branch
consolidation executed. Updated: 2026-10-26.** Eleven local/remote working branches
remain: master, M1 and nine protected research topics. See the
[execution record](evidence/phase-a/2026-10-26-branch-consolidation.md).
R0–R4 below describe the completed campaign, not instructions to recreate retired
migration branches. M1 feature acceptance remains separate.
The canonical compiler-only commit is `ae7197d`, based on live remote master
`497d346`. The [final ledger and evidence](evidence/phase-a/2026-10-26-zig-0.17-rollout.md)
record source/delivery SHAs, separate branch gates and retained exclusions.
Branch integration uses the exact canonical commit and reviewed compatibility
patches; the allocator siblings reuse their tested shared-parent adaptation. Preserve research
contracts and historical 0.16 evidence; do not merge research features into master
as a side effect. No force-push, global compiler switch or other-session checkout
is required.

## Starting point and first action

The M1 worker is verified on 0.16.0 at `b43f5df`. A real 0.17.0 probe fails at
`build.zig:80`: `std.Build.args` was removed. This is the first discovered blocker,
not a complete error inventory. See [readiness evidence](evidence/phase-a/2026-10-25-zig-0.17.md)
for compiler paths/hashes, live remote refs and the failed probe.

**Historical R0 upstream check:** local/cached master was `11c3319` while live
remote master was `497d346` after lab PR #1. The migration used the live baseline,
not the stale local ref. Compiler PR #2 subsequently merged as `dc06c64`; local
master now tracks actual remote master. Always refresh upstream before new work,
without moving another live Pi session's branch. M1 is still not on master.

## Complete branch ledger

This is the historical inventory of 14 source profiles, not the current head
list. The rollout ledger records their verified delivery tips. The subsequent
[disposition](evidence/phase-a/2026-10-26-branch-consolidation.json) records retained
source names and retired aliases: all nine research topics and M1 received their
0.17 histories; completed profiles remain recoverable through immutable tags.

| Branch | Inspected source tip | Order / branch-specific gate |
|---|---|---|
| `master` | local `11c3319`; live remote `497d346` | R1; core, OTP 25/26/27, labs and negative compile tests |
| `explore/lab-contracts` | `2fa1911` | R2; already upstream; all 22 lab cases and both expected failures must retain their intent |
| `docs/worker-lifecycle-plan` | `4aa7333` | R2; code follows canonical compiler commit; roadmap remains appropriate to this branch's actual implementation |
| `feat/monitorable-worker` | `a9e13a9` clean R0 checkpoint; behavior at `b43f5df` | R2; core, upstream labs, PID/named monitors, all 13 owner scenarios and guard checks |
| `feat/worker-lifecycle` | remote-only `38caeb4` | R2; reliability/SHA-256 and OTP regression; do not substitute the newer M1 profile |
| `explore/zigler-baseline` | `d0f9ff2` | R3 root; native comparison workers plus independently verified Zigler compiler compatibility |
| `explore/batched-requests` | `8f161ea` | R3; batch bounds, malformed batches and exact per-item results |
| `explore/beam-backpressure` | `7f3e5fb` | R3; demand/idle-tick policy, pause/fault tests and finite blocked-write/timeout cases |
| `explore/io-overhead` | `d6656b0` | R3; frame profiler, partial/coalesced I/O and ownership/allocation-count regressions |
| `explore/worker-recovery` | `e08175e` | R3; original experimental owner/fault campaign, no replay; keep distinct from M1 owner semantics |
| `explore/actor-admission` | `ddf5ece` | R3; fixed two-worker admission, conservative credits and joined-operation cleanup |
| `explore/allocator-baselines` | remote-only `27b0fee` | R4 root; explicit process/debug/smp/libc variants and allocator provenance |
| `explore/request-arena` | remote-only `ff5ac17` | R4 after allocator root; arena reset, maximum request, failure cleanup and no lifetime escape |
| `explore/snmalloc` | remote-only `62c511c` | R4 after allocator root; pinned external object, allocator ABI/alignment/resize/remap/free checks |

## R0 — Freeze a recoverable baseline

1. Record fresh `ls-remote`, local refs, worktree owners/dirty state and commit
   ancestry. Coordinate with each active Pi session before updating its branch.
2. Preserve immutable pre-migration SHA/tag references for all 14 branches; publish
   backup tags only through the normal reviewed Git workflow. Do not rewrite old
   evidence or move an existing tag to make a failure disappear.
3. Re-run each branch's available 0.16 gates first. Missing tools, a failed
   historical baseline, or an unavailable remote-only branch must be recorded as
   blocked, not passed. Target names differ: inspect `build.zig`; not every branch
   currently defines `test-all`, stress or interop aliases.
4. Pin the exact 0.17 compiler/archive provenance and checksum in CI and per-command
   execution. Retain the explicit 0.16 compiler for rollback. Use separate caches
   and install prefixes for compiler/allocator variants; do not alter global PATH,
   mise settings, symlinks or another worktree's build output.

**Exit:** reproducible 0.16 baselines, owned worktrees and a complete migration
ledger with old SHA, toolchain, target list, outcome and evidence path per branch.

## R1 — Make the canonical master compile and preserve contracts

Create `migrate/zig-0.17-master` from the refreshed remote master in a new worktree.
Split review into build/API adaptation and verification/metadata, keeping each
behavioral adjustment with its regression tests.

| Surface | Required migration work |
|---|---|
| Build configuration | Adapt the new 0.17 build/configurer API, starting with removed `b.args`. Verify argument forwarding for executable/benchmark targets rather than deleting it. Preserve battery imports, opt-in lab steps and expected-failure steps. |
| Standard library | Compile through every ETF/protocol/transport/actor/runtime module, tools and examples. Resolve only observed API changes. Audit Reader/Writer, process startup, sockets, timers, atomics, allocation and `std.Io` task cancellation/join semantics against the installed 0.17 sources. No legacy-I/O shim or scheduling redesign. |
| Ownership/errors | Preserve positive-demand reads, partial-frame limits, aggregate decoded budgets, explicit allocator owners, thread-safe mailboxes and cancellation propagation. A compiling replacement is not sufficient if these contracts change. |
| Compiler diagnostics | Check negative fixtures by intended compile-time invariant, not a pinned line number or accidental syntax error. Update diagnostic matching only after proving the same invalid program is rejected for the right reason. |
| Package/CI/docs | After gates pass, update `.minimum_zig_version`, both CI compiler pins, contributor requirements, current README/status and reproducible commands. Keep package version unchanged unless separately released; historical logs/spec snapshots keep their original compiler labels. |

Run independent battery/package-consumption checks and all common gates below.
Review the actual 0.17 allocator source/binary selection again; the 0.16
DebugAllocator audit is not evidence for 0.17's default allocator or I/O backend.

**Exit:** a compiler-only candidate based on current remote master, passing
`debug` and `safe` core/labs plus actual OTP 25/26/27. No M1, allocator or research feature
is promoted merely to make this migration easier.

## R2 — Propagate the canonical commit to baseline and M1 branches

Create `migrate/zig-0.17-<branch>` branches from recorded source tips and merge the
**exact canonical migration commit**, not an unreviewed moving master. This brings
accepted upstream labs where absent; it must not flatten each branch's distinct
runtime/benchmark contract. Preserve history rather than rebasing published work.

During R0–R4, the session-owned migration worktree was reused after clean commits
to share compiler caches, while nine original worktrees remained untouched.
The later explicit owner-authorized handover is recorded separately; it did not
switch a checkout belonging to another live Pi session.

Start with lab-contracts and the docs branch, then the foundation lifecycle branch
and M1. Resolve M1's build and runtime additions on its own branch. Its additional
acceptance includes:

- correlated discovery/hash/stop and stale-PID handling;
- PID and named monitors, `noproc`/`normal`/`noconnection`, demonitor and bounded table cleanup;
- guard EOF/TERM/KILL, owner/VM death, caller admission/death and restart intensity;
- panic/allocation/spin/private-EPMD scenarios, late-reference rejection and no replay.

Merging compiler work is not permission to integrate M1 into master. Re-run the
combined labs against the expanded ETF representation; previous isolated lab
results do not verify that combination.

**Exit:** each R2 row has a tested new SHA, old SHA, compiler hash and evidence.
The docs branch must not acquire an inaccurate "implemented M1" inventory merely
because it received a compiler update.

## R3 — Migrate each native comparison branch without invalid benchmarks

Use `explore/zigler-baseline` as a compatibility-patch source, not a wholesale
merge of its benchmark features into sibling branches. Apply only reviewed shared
compiler adaptations; retain each sibling's request shape and safety checks.
Available branch-specific build targets include `build-research`, `test-research`,
`build-research-peer` and `build-frame-profile`; use only the targets present in
that branch. Run its Python self-checks and Elixir/Mix correctness checks as well.

**The demonstrated Zigler blocker is resolved for eligible adapters.** The original
0.16 project fails generated `b.args` on 0.17. The exact upstream Git pin
`feb80162d597ede227e9d4d5c9798a42beee9695` passes fresh-VM correctness checks;
[dependency evidence](evidence/phase-a/2026-10-25-zig-0.17-zigler.md) records its
unreleased status, helper locks and retained threaded quarantine. Check upstream support
for 0.17, isolate any necessary dependency/adapter update and run malformed-input,
exact-result and scheduler-mode tests in fresh VMs. Never silently use 0.16 for
NIFs while calling the whole branch 0.17 or declaring a matched-compiler speedup.
If support is unavailable, mark native migration partial and the branch blocked;
keep the old comparison reproducible. The quarantined threaded-NIF path stays
quarantined unless a separate safety review clears it.

Run correctness smoke trials before any full measurement. A benchmark claiming
0.17 results requires fresh source/binary/toolchain manifests, fresh serial runs
and current allocator provenance; 0.16 measurements remain historical. Do not
combine compiler migration with batching, zero-copy or scheduler optimizations.

**Exit:** every R3 branch compiles all its own Zig code under 0.17, passes its
contract/failure checks, and has an honest matched-toolchain comparison status.

## R4 — Migrate allocator research in ancestry order

`27b0fee` is the shared parent; request-arena and snmalloc are siblings. Port the
allocator baseline first and reuse only its compiler adaptation in the siblings.
Keep these experiments out of runtime batteries and do not change the default
allocator on master.

Verify allocator vtable signatures and alignment units against 0.17, including
zero/small/large allocation, failed growth, resize/remap ownership, exact free and
thread/lifetime expectations. Rebuild pinned snmalloc objects with recorded
compiler/C++/libc/ABI flags; old objects are not assumed compatible. Check both
`snmalloc-resize` modes and existing libc-linkage controls on native Linux x86-64
GNU ABI. Arena reset must not invalidate an escaped response or in-flight task.

Use `scripts/bench/allocator_matrix.py` with newly built, separate install prefixes
and a new output directory. Preserve old result directories, input sizes, sample
validation and failure semantics. Repeat source/symbol allocator-routing audits
before attributing a change in RSS or latency to an allocator.

**Exit:** all allocator variants and failure/ownership checks pass; any new
performance conclusion has independently regenerated 0.17 evidence.

## Common verification and promotion

Run equivalent explicit targets when a branch lacks an aggregate alias:

```sh
"$ZIG_017" fmt --check build.zig src tests examples
"$ZIG_017" build
"$ZIG_017" build test-unit test-integration test-conformance test-stress -j2 --summary all
"$ZIG_017" build test-unit test-integration test-conformance test-stress -j2 -Doptimize=safe --summary all
"$ZIG_017" build test-labs -j2 --summary all
"$ZIG_017" build test-labs -j2 -Doptimize=safe --summary all
"$ZIG_017" build test-interop-docker -j2 -Doptimize=safe --summary all
```

`test-labs` requires upstream lab integration; missing required aliases on a
research branch need equivalent explicit checks, not a silent skip. Format/build
all branch-owned Zig tools and benchmark sources too, not only these directories.
M1 additionally runs `test-worker-recovery` in both modes and OTP in `debug`;
external Elixir/OTP compatibility is recorded separately from native wire support.
CI should expose required external-tool lanes rather than hiding them in test-all.

The [retention policy](branch-consolidation-plan.md) is now executed: 28 names
became 11 locally/remotely, while all nine research topics and M1 remain working
branches. Fourteen annotated 0.17 snapshots and existing 0.16 tags preserve the
retired profiles; ignored assets were separately backed up. No blanket research
retirement or feature promotion accompanied the compiler merge.

Refresh heads and verify the current merge result for any future promotion.
Compiler PR/merge and M1 handover CI passed. Earlier M1 `64f6388` failed OTP 27
safe registration; later green runs do not establish its root cause or corrective
fix. Retain it for acceptance triage and require current checks.
Normal ancestry, not similar contents, determines whether a fast-forward is valid.
Never reset, force-push or move a branch behind a live worktree.

The **14/14 local candidate verification** record remains complete. Branch
retention, current GitHub checks, owner coordination and feature acceptance are
separate decisions. A newly blocked required gate reopens its acceptance. Retain
pre-migration refs; rollback through a reviewed revert/new commit or explicit
old-toolchain deployment, not rewritten history.
The [development plan](development-plan.md) remains responsible for M2/runtime
features after this compiler-only rollout.
