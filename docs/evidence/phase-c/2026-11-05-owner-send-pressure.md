# Confirmed-unsent owner requests under distribution pressure

**Scope:** candidate based on M2c master `29f03e40a2604fc945c08549869047096e01d0d5`; Linux WSL2 x86-64, Elixir 1.20.4 / OTP 29.1.1, Zig 0.17.0. This changes the Elixir example only, not the M1/M2b wire profiles or native service.

## Contract and source

[`erlang:send/3` in OTP 25](https://www.erlang.org/docs/25/man/erlang.html#send-3), [OTP 26](https://www.erlang.org/docs/26/man/erlang.html#send-3) and [OTP 27](https://www.erlang.org/docs/27/apps/erts/erlang.html#send/3) specifies that `ok` sends the message and any other result does not. The owner now returns `busy` and releases only the matching admission on `:nosuspend`. It leaves an earlier `:ok` sibling pending; `:noconnect`, caller loss and uncertain timeout retain fail-closed recovery. There is no automatic retry.

## Local check

Run the owner suite against the existing `zig-out/bin/zbeam` built from the accepted M2b service:

```sh
sh scripts/interop/ensure_epmd.sh
elixir --erl '+S 2:2' --name CLIENT@127.0.0.1 --cookie COOKIE \
  tests/interop/two_worker_owner_test.exs ./zig-out/bin/zbeam
```

The added test stops the native process, sends a 1 MiB request to `a`, and uses bounded test-only malformed-command traffic to fill the distribution buffer. Five consecutive `:nosuspend` outcomes establish sustained pressure before submitting a 1 MiB request to `b`. The public call returns `busy`; the same owner and `a`'s ticket survive, while `b`'s ticket is released. After resuming the native child, `a` returns the exact digest and a fresh `b` request succeeds. This bypass traffic exists only in the test; normal applications must preserve exclusive owner use.

The suite passed **11/11** once after the pressure setup and in **five additional fresh VMs**. The original attempt, which submitted just two large messages without filling the socket, timed out waiting for the second call in this environment; that failure is retained at `~/.local/state/zbeam-maintenance/2026-10-29-m2d/owner-first.log`. It does not establish why the prior M2c probe returned `:nosuspend`. The successful run and repetitions are retained beside it as `owner-pressure.log` and `owner-repeat-{1..5}.log`.

The existing suite also covers a dead caller before delivery and during work, uncertain timeout, stale references and disconnect.

On this candidate, `zig fmt --check build.zig src tests examples` passed, and each of the following completed **73/73 steps; 168/170 Zig tests passed, two conditional skips** (the opt-in spin test is exercised separately by the watchdog subprocess):

```sh
zig build test-all test-labs test-task-lifecycle test-worker-recovery -Doptimize=debug -j2 --summary all
zig build test-all test-labs test-task-lifecycle test-worker-recovery -Doptimize=safe -j2 --summary all
```

Each run included the Elixir owner and process-recovery suites. Logs are `full-debug.log` and `full-safe.log` in the local ledger above. `zig build test-interop-docker -Doptimize=safe -j2 --summary all` also passed **7/7 steps, three pinned OTP 25/26/27 targets and none missing**, including actual CLI EPMD loss; the native service compilation was cached. This is wire-profile evidence, not an Elixir owner test on those OTP versions. Its log is `otp-docker-safe.log` in the same ledger.

These checks do not establish a physical memory or fairness bound, nor do they prove delivery when the distribution connection is saturated. Elixir/OTP 25–27 and actual merged-master CI are separate gates, not implied by the local run.

**Rollback:** revert this focused owner change, test and documentation together; prior `:nosuspend` behavior fails the owner closed.
