# M2c handled retirement — 2026-10-29

The owner test injects a correlated `handler_failed` reply while worker `a` is
paused, then resumes the actual process. It verifies the pending caller receives
that error, `a` stays unavailable and `b` computes a fresh exact digest. The
later real old reply is not used for the new call. The injected reply exercises
the Elixir owner branch; it is not an actual native SHA-256 handler failure.
The native actor failure boundary is tested separately by the M2a lifecycle
suite. Controlled wire retirement is covered by the main owner test.

Linux/WSL Elixir 1.20.4 / OTP 29: all ten owner cases passed in 20 fresh VMs.
Zig 0.17.0 debug and safe recovery passed 5/5 steps each. Roll back this test
and evidence together; no production behavior changes.
