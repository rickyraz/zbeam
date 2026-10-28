# M2c pre-mailbox admission — 2026-10-29

`TwoWorkerAdmission` validates actor/input before an ETS claim and returns the
owner PID and table reference from the same live table. The table owner must
also be the registered owner. One slot per actor is claimed atomically before
sending a payload to that owner. Exact ticket matching, explicit release and
abandoned-caller detection are internal primitives; no M2c owner is published.
ETS bounds these API claims, not arbitrary BEAM messages or total RSS.

Linux/WSL, Elixir 1.20.4 / OTP 29: four ExUnit cases passed in 50 fresh VMs
(4,000 racing claim attempts); each actor admitted exactly one of 40 callers.
`zig build test-worker-recovery -Doptimize=<debug|safe> -j2 --summary all`
passed 5/5 build steps per mode, including admission, all complementary M1
owner cases and both existing M2b process-loss runs. Test-only EPMD is isolated.

The first attempt failed 0/3: `:ets.new` returns the name for a named table,
whereas `:ets.whereis` returns its table reference. The test fixture was fixed
to compare the reference actually returned by admission; the original log is
retained. No production M1 or native Zig behavior changed. Rollback removes the
helper, its tests and recovery-script hook together. Lifetime and cleanup are
not established for an owner until the next unit composes and tests them.
