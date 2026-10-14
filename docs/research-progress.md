# Native-worker research progress

**Decision:** no evidence currently supports promoting zbeam as faster than direct Zigler NIFs or Ports. Research branches remain separate from `master`.

## Repeated baseline

The 2026-10-03 matrix completed 390 independent VM launches and 390,000 timed, exact-result-checked requests. Each eligible job/path/size combination has ten launches. Payloads: 32 B, 4 KiB, 64 KiB and 1 MiB. Modes: normal/dirty NIF, raw Port, ETF Port and distribution; 1 MiB synchronous SHA-256 was excluded. Zigler threaded mode is quarantined after incorrect results and a test-VM segfault, not counted as a defeated comparator.

Median-of-launch p50 for SHA-256:

| Input | Direct NIF | Dirty CPU NIF | Raw Port | ETF Port | zbeam |
|---|---:|---:|---:|---:|---:|
| 32 B | 0.210 µs | 1.754 µs | 37.266 µs | 106.562 µs | 578.310 µs |
| 64 KiB | 52.315 µs | 62.033 µs | 241.738 µs | 544.956 µs | 811.607 µs |

Environment: Zig/Zigler 0.16.0 ReleaseSafe, OTP 29.1.1, Elixir 1.20.4, four-CPU Linux x86-64/WSL2; two normal and two dirty CPU schedulers. These are unloaded sequential application measurements, not CPU-only attribution or production guarantees. The existing code preserves finite deadlines and bounded owned-copy processing.

Raw files remain at `docs/evidence/phase-c/2026-10-02-native-comparison/repeated/` in this checkout; the current local ignore policy excludes new evidence files from Git. The manifest records source/binary hashes, seeded ordering, exclusions and resource sampling limitations. Every recorded p50/p95/p99 was recomputed from the 390,000 raw samples on 2026-10-13. The runnable matrix and dependency lock are committed. Native-host replication and loaded-BEAM measurements are still absent.

## Resume checkpoint — 2026-10-13

The five temporary experiment worktrees under `/tmp/zbeam-research-20261002` no longer existed at resume. Their uncommitted changes and local verification logs were not recoverable from Git. Earlier session output is historical, not current-checkout evidence. Branch references and committed baseline tooling survived.

Replacement worktrees are persistent siblings at `../zbeam-research/{io-overhead,beam-backpressure,worker-recovery,batched-requests,actor-admission}`. The experiments below were restored, tested again and committed; missing historical logs are not substituted for these new checks. The main-worktree `.gitignore` and mailbox edits present at resume were excluded from these research commits.

## Restored experiment results — 2026-10-13

Each branch contains its corresponding `docs/evidence/phase-c/2026-10-13-*.md` record and raw logs. The optional pause/fault peer is shared by pressure, recovery and admission branches; no runtime battery imports research tooling.

| Branch | Implemented and executed | Decision |
|---|---|---|
| `explore/io-overhead` | Rollback-safe ETF append API, allocation/deadline profiler, 57-test Debug/ReleaseSafe suites, OTP 25/26/27; 80 paired VM launches / 80,000 exact-result samples | 64 KiB echo throughput ratio 1.137 [1.098, 1.182] against original zbeam; no established SHA-256 gain and unresolved p99 regression risk. Not promoted. |
| `explore/beam-backpressure` | Optional bounded pause/fault peer, 54-test Debug/ReleaseSafe suites, nine pause trials and three owned-process fault checks | 500/3500 ms pause/resume passed; 8000 ms pauses disconnected under four-second ticks and subsequently reconnected. No indefinite-pause heartbeat guarantee. |
| `explore/worker-recovery` | External single-flight owner, non-suspending submission, timeout teardown, owner contract checks, 54-test Debug/ReleaseSafe suites; sixty restart trials across six fault modes | Explicit failed-request outcomes and fresh successful requests; no replay. Raw Port isolation also passed, so recovery is not a Port performance advantage. |
| `explore/actor-admission` | Ownership/admission ADR, two-mailbox joined stress test, 56-test Debug/ReleaseSafe suites, twenty stress repetitions, ten two-process progress controls | Local and separate-process progress verified; shared-wire multi-actor dispatch and matched throughput remain unimplemented. |
| `explore/batched-requests` | Correlated 1–32 independent-job batches, 1 MiB aggregate/2 MiB frame bounds; 59-test Debug/ReleaseSafe suites, OTP 25/26/27, four matched comparator smokes and dirty-NIF tests | Correctness established for the stated subset; preformed-batch measurements are separate from application fill wait and performance promotion. |

These are six research tracks including the repeated baseline, not six production promotion approvals. `master` remains at `11c3319`; no push or merge was performed. The unrelated `explore/lab-contracts` worktree is outside this experiment lineage.

## Remaining gates

- Native Linux replication and loaded-BEAM fairness.
- Threaded Zigler comparator safety; it remains quarantined rather than counted as defeated.
- Batch fill-wait and complete resource/tail-regression budgets.
- Long-running producer queue/RSS accounting and production process-tree supervision.
- Shared-wire multi-actor dispatch, dynamic-size admission and matched two-actor/two-process throughput.
- Promote no candidate merely because allocation counts, batching amortization or crash isolation improve one isolated observation.

The [research plan](native-worker-research.md) remains the acceptance contract, not a completion checklist.
