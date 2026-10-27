# M2a public API and integrated regression candidate

The production-mode `example-task-runtime` instantiates the additive API without
test hooks: three exact SHA-256 jobs across both actors, retirement of one actor,
sibling reuse, shutdown and result exhaustion. `test-task-lifecycle` now runs it
as well as the deterministic tests/watchdog. The public stress test joins eight
external senders before runtime teardown and conserves every accepted request.

Linux x86-64 WSL2 / Zig 0.17.0, watchdog merge base `baf2be3` plus this PR's
example/stress/build delta (no task-owner or wire implementation delta):

- Full core/labs/lifecycle debug/safe: 69/69 steps each, 38/39 newly executed
  checks passed with one conditional spin skip; unaffected runs cached. The
  separate kill/reap probe and production-mode exact example passed both modes.
- Public stress: 100 fresh launches per mode, 102,600 actor-A send attempts
  including initial requests, plus 200 exact sibling requests. Accepted actor-A
  requests stay within 2–5; accepted/terminal ID sets match with no duplicates.
  Debug distribution: 5=82, 4=2, 3=10, 2=6; safe: 5=97, 4=2, 3=1.
- Actual pinned OTP 25/26/27: 7/7 build steps, three targets passed/missing zero
  in each mode, preserving M1 PID/named-monitor, reconnect and isolation checks.
- Existing guarded owner: 4/4 build steps each mode; complementary ExUnit runs
  report 13 passed/1 excluded and 1 passed/13 excluded, hence all 14 cases per
  mode executed, plus guardian and exact monitored-worker example. Elixir
  1.20.4 / local OTP 29; distinct from native OTP 25/26/27 compatibility evidence.
- Raw full, matrix, recovery and fresh stress logs retained adjacent. Formatting,
  whitespace and changed-document links checked. No new performance evidence.

This is the local integration candidate, not final master acceptance. Candidate,
PR and actual-master CI must pass before the status closure; skipped spin cases
are never credited as successful probe execution. M2b remains gated and disabled.
Rollback removes the standalone example/public stress/build wiring/docs only;
accepted ownership, lifecycle and watchdog units remain independently usable.
