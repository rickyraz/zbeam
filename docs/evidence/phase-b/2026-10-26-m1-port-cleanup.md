# Close owned Ports without a check/use race — 2026-10-26

**Status:** repair verified locally; fresh candidate/PR/master checks still gate
M1 acceptance. This is external-owner/test cleanup, not a native wire change.

[PR #3](https://github.com/rickyraz/zbeam/pull/3) merged normally as
`2241e7f4a93b5a5e0ff533169494312ade71b34e`, after explicit owner size-exception
approval and 9/9 candidate plus 9/9 synthetic-merge CI jobs. Actual master has
exactly the candidate tree. Its [new CI run 40348895214](https://github.com/rickyraz/zbeam/actions/runs/40348895214)
passed eight jobs but failed `worker-recovery (debug)`: all twelve ordinary
cases and the exact example passed; the private-EPMD case raised `ArgumentError`
at `:erlang.port_close` after TERM had already closed that Port. Acceptance was
reopened; the failed run was not blindly rerun or counted as success.

`Port.info` followed by `Port.close` is a check/use race. A controlled counterexample
captures non-nil info, closes the resource between those operations, then
reproduces the same exception. Owner and test cleanup now attempt close directly,
catch only `ArgumentError`, and tolerate it only when the Port is confirmed gone.
An invalid argument or error involving a still-live Port remains an error.
The private-EPMD fixture explicitly waits for its owned daemon's exit before
exercising closed-Port cleanup. VM-loss cleanup uses the same test helper.

One additional ordinary regression exercises both cleanup paths with open,
already-closed and invalid Ports. The original thirteen complementary scenarios
remain: **13 ordinary + 1 private-EPMD case = 14 current cases per mode**. No
request/reply, admission, timeout, guardian, restart or no-replay assertion was
removed. Native sources, battery boundaries and accepted ADRs are unchanged.

## Verification

Linux x86-64 WSL2, Zig 0.17.0, Elixir 1.20.4 / OTP 29, `.zig-cache/0.17`:

- Actual merged master before this repair: build 5/5; core/labs 63/63 and 91/91
  executed tests per mode; pinned native OTP 25/26/27 both modes 7/7, zero missing;
  local original recovery 4/4 and all thirteen cases per mode; five startup cases,
  guardian and argument smoke passed. Local success did not erase remote failure.
- Repair: `zig build test-worker-recovery -Doptimize=debug|safe -j2 --summary all`,
  ten complete campaigns per mode, each 4/4 steps and all fourteen cases;
  **20 campaigns / 280 ExUnit case executions**. Each campaign also runs guardian,
  the exact three-job example and fresh private-EPMD VM. This is regression
  repetition, not long-soak or performance evidence.
- `mix format --check-formatted` checks the two touched Elixir sources. Core/labs,
  documentation links and whitespace are rechecked before commit.

Raw failures, the intended counterexample and local results are retained in
`2026-10-26-m1-port-cleanup/`. Current CI must execute every required lane before
integration; later green checks do not retroactively change the failed run.
