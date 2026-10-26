# Pre-migration commit grouping and clean checkpoint

**Date:** 2026-10-25. **Compiler baseline:** Zig 0.16.0.

All nine existing worktrees were clean, including untracked files, before any
compiler migration edits. Published history is retained rather than squashed or
force-pushed. The current implementation groups are:

| Work unit | Commits | Verification boundary |
|---|---|---|
| Original M1 plan | `4aa7333` | Documentation only |
| Reliability and fixed SHA-256 foundation | `7b812d3`, `c47968d`, `38caeb4`, integration `9459ca2` | W0 Debug/ReleaseSafe and OTP 25/26/27 |
| Initial lifecycle decision | `04d6d2b` | Original ADR preserved; later superseded |
| Bounded references and pure controls | `27ba7d1` | W2 59/59 and actual reference vectors |
| Worker identity and correlated requests | `99928a0` | W3 62/62 and OTP matrix |
| PID/named process monitors | `50b315b` | W4 69/69 and OTP matrix in both modes |
| Independent Linux child ownership | `5502b2c`, test race fix `ca3fe1b` | Four guard boundaries, 20 repetitions |
| External owner and failure campaign | `b43f5df` | W5 core 69/69; 13 owner scenarios per mode; OTP regression |
| Current contracts and immutable ADR supersession | `a22412c` | Documentation and original-ADR comparison |
| All-branch compiler plan | `3b6ce25` | Documentation, source inventory and expected-failing 0.17 probe |

Code, tests and relevant contract documents remain in their corresponding units.
The owner campaign is an oversized cohesive unit (1,142 changed lines including
raw evidence); it is not relabelled as a small review. No new PR or history rewrite
is part of this checkpoint. Subsequent compiler adaptation is a separate concern.

The local master remains `11c3319`; the verified live remote master is `497d346`
with accepted labs. M1 is not merged into master. Immutable local tags under
`archive/zig-0.16/` retain the fourteen pre-migration branch tips, with a separate
`archive/zig-0.16/local-master` for the stale local master. Migration occurs only
in new `migrate/zig-0.17-*` worktrees; original active worktrees remain untouched.

The [migration plan](../../zig-0.17-migration.md) defines the per-branch gates.
Existing [M1 evidence](../phase-c/2026-10-25-m1.md) remains historical 0.16 evidence.
A clean checkpoint is not a passing 0.17 result.
