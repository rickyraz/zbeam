# M2c restart name/connection barrier — 2026-10-29

A candidate owner fault test initially failed after SIGKILL of its owner: the
supervisor did not publish a replacement within five seconds. The initial
launcher immediately rejected an already-connected peer. That source path can
race guardian cleanup, but the failed run did not capture the unique cause.
The original failure is retained.

A controlled counterexample starts an existing peer, starts a replacement while
the old connection is still live, then closes the owned old process. The old
launcher returns `not_ready` instead of waiting; its failing log is retained.
The repaired launcher waits within its existing deadline for both the BEAM
connection and EPMD registration to disappear. It neither disconnects nor
kills an occupied peer. A still-occupied name returns `name_taken`.

Linux/WSL Elixir 1.20.4 / OTP 29: four launcher tests passed in 25 fresh VMs;
the candidate owner with this launcher passed eight tests in 20 fresh VMs,
including owner SIGKILL and two uncertain requests. Zig 0.17.0 recovery passed
5/5 steps in debug and safe. These are separate tests, not proof of production
availability or immunity to malicious local name races. Roll back the wait and
its tests together; a premature rejection would restore the observed risk.
