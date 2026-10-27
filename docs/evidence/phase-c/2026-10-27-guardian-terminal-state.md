# Guardian oracle correction after documentation-PR failure

PR #13's initial head `d93a9a5`, run **40470016562**, passed 8/9 jobs but failed
`worker-recovery (safe)` before ExUnit. The guardian kill subcase's final
`assertFalse(live(native))` observed True. All four boundary subcases completed
in 0.232 seconds, below the unchanged three-second polling budget. The same
head's push run 40470011719 passed 9/9; that does not erase the failed PR run.
Raw original job log and both complete outcomes are retained adjacent.

## Demonstrated oracle defect, evidence limit

The test already polled; it was not an immediate-after-kill assertion. Its
`live` helper recognized only `Z`, then re-read procfs after the loop and again
in cleanup. Linux [proc_pid_stat(5)](https://man7.org/linux/man-pages/man5/proc_pid_stat.5.html)
defines `Z` as zombie and `X` (legacy `x`) as dead. Controlled `Z -> X` snapshots
make the old loop stop and its redundant final probe fail despite both states
being terminal. A comm field containing `) Z ` also fooled the substring check.
The original runner did not retain stat snapshots; **X is not asserted to be
the uniquely proven historical cause**. The source-supported oracle class is
fixed, not hidden by a retry or a longer deadline.

## Correction and verification

- Parse state after the final comm parenthesis; treat `Z`/`X`/`x`, ENOENT and
  ESRCH as non-live. Stopped/sleeping/uninterruptible states remain live.
  Permission and malformed-record errors remain failures.
- Poll until a terminal observation or the original three-second deadline.
  Do not re-probe or send a cleanup signal after that terminal observation;
  this also avoids treating subsequent PID reuse as the original owned child.
- Deterministic tests cover all documented terminal forms, embedded parentheses,
  missing/ESRCH, permission/malformed failures, no redundant probe and actual
  timeout when a process stays live. Guardian/child production code is unchanged.
- Linux x86-64 WSL2/Python 3: 100 complete launches, 300 unittest methods and
  **400 real EOF/TERM/KILL/child-exit boundaries** passed. No local spontaneous
  reproduction is claimed; the controlled old-oracle counterexample is retained.
- Zig 0.17.0 core/labs/lifecycle debug/safe: 69/69 steps, 32/33 newly executed
  checks passed with one disclosed spin skip and unaffected cached runs.
  Owner both modes: 4/4 steps; all 14 complementary ExUnit cases, guardian and
  exact monitored example passed. Final candidate/PR/master CI remains required.

This is a verification-only repair, not a weaker process-ownership contract or
an M2 runtime change. No shared EPMD or unrelated process was killed. Rollback
restores only the guardian oracle/tests and these verification notes.
