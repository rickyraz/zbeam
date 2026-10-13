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

Replacement worktrees are persistent siblings at `../zbeam-research/{io-overhead,beam-backpressure,worker-recovery,batched-requests,actor-admission}`. Each restored experiment must be tested again and committed independently. No missing experiment is marked complete by this checkpoint. Existing main-worktree edits to `.gitignore` and `src/zbeam/actor/mailbox.zig` are outside these research commits.

## Remaining gates

- Profile and test the encoder candidate; separate allocation/copy changes from deadline-task overhead.
- Execute OTP-sender pause/resume and heartbeat-boundary experiments.
- Verify repeated external supervision, explicit failed-request outcomes and test-owned process cleanup.
- Restore bounded correlated batches and equally batched NIF/Port controls.
- Verify two-worker admission and joined storage lifetime; do not claim a production scheduler.
- Repeat on native Linux; resolve threaded NIF uncertainty independently; publish promotion decisions with all regression budgets.

The [research plan](native-worker-research.md) remains the acceptance contract, not a completion checklist.
