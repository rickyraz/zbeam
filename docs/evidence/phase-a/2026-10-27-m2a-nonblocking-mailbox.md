# M2a prerequisite: nonblocking mailbox admission

`Mailbox(T).tryDeliver` attempts one complete element using Zig 0.17 queue
`put(..., min = 0)`. It returns `WouldBlock` at capacity and retains caller
ownership on any error. It never links a pending putter; mutex contention may
still block/cancel. Existing blocking `deliver` and close/drain behavior stay
unchanged. This is an actor-battery primitive, not a delivered task runtime.

Linux x86-64 WSL2, Zig 0.17.0, base accepted design merge `9c87d15`:

- `zig build test-all test-labs -Doptimize=debug|safe -j2 --summary all`:
  each 63/63 steps, 58/58 newly executed tests; unaffected test runs cached.
- Focused `nonblocking` tests verify full rejection, drain order, closed rejection,
  no pending putter and canceled contended insertion with zero transfer.
- Each focused binary executed 100 fresh launches per mode (200 cases per mode).
  The cancellation test holds the actual queue mutex and joins the canceled
  sender before inspecting queue state; no sleep establishes its interleaving.
  Each runner also executes the module declaration check (three tests/launch).
  Archive validation initially expected two runner tests; that bookkeeping
  assertion was corrected to include the root test, without rerunning failures.
- Formatting and whitespace checked. No transport/wire/flag change; existing OTP
  CI remains the regression gate, not proof of task ownership.

Adjacent raw logs preserve the full build and focused launch summaries. Rollback
removes `tryDeliver` and its tests without changing the caller-owned registry.
M2a payload ownership, task startup and stop/join remain subsequent work units.
