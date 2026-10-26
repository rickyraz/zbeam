# In-flight admission send accounting — 2026-10-26

## Observed failure

After the branch-pair handover, `explore/actor-admission` at `b3d1299` failed
[CI run 40287150328](https://github.com/rickyraz/zbeam/actions/runs/40287150328):
the safe stress test expected five slow-worker messages but observed six.
Its native OTP lanes passed. The earlier migration-branch run at the same SHA
passed; that does not erase this failure. The old assertion did not fail in
100 additional isolated local launches, so local reproduction is not claimed.

## Contract and correction

The existing caller-managed lifetime contract requires joining resolved sends
before storage destruction. It does not guarantee that every in-flight send
fails when termination starts. Zig 0.17 `std/Io.zig` implements `Queue.close` by
marking closed and waking waiters; a pending put remains linked until resumed.
`getLocked`/`fillRingBufferFromPutters` can consume that pending put during drain.
A send already in flight may therefore finish; new puts still fail `Closed`.

The test now conserves exactly the actual outcome: five consumed messages if the
send fails `Closed`/`ActorNotFound`, six if it succeeds. It additionally proves
that new named sends fail `ActorNotFound` and new direct deliveries fail `Closed`
after termination. Independent fast progress, capacity, worker errors and task
joining remain asserted. No runtime, mailbox implementation, API, ADR or scheduler
behavior changes; the correction removes an unsupported scheduling assumption,
not the delivery accounting invariant.

## Verification

Linux x86-64 WSL2, Zig 0.17.0; separate `.zig-cache/0.17`.

- Isolated test executable in debug and safe: 100 launches per mode, two tests per
  launch; all 400 case executions pass. Raw logs identify the actual test count.
- `zig build test-all test-labs -j2 --summary all`: 63/63 steps, 78/78 tests passed.
- Same command with `-Doptimize=safe`: 63/63 steps, 78/78 tests passed.
- `zig fmt --check tests/stress/two_worker_admission.zig` and whitespace checks pass.

Raw failed CI, both gate logs and repeated-case logs are in
`2026-10-26-admission-close/`. This is correctness evidence, not a throughput or
production-safety claim. Current commit CI must still run normally after push.
