# M2c Elixir/OTP matrix gate — 2026-10-29

CI adds three safe-mode owner/recovery lanes: Elixir 1.17.3 with OTP 25, 26
and 27 on Ubuntu 24.04. The existing Elixir 1.20.4 / OTP 29 recovery lanes
retain debug and safe. The independent native OTP 25/26/27 wire matrix keeps
both optimization modes. Each owner lane runs the actual guarded example,
owner/process faults and M1/M2b recovery, not only a compile check.

This change configures tests; it does not itself prove that any new lane ran.
Candidate and actual-master job results must be recorded separately before
acceptance. A setup/install failure or missing lane is not a pass. Revert this
matrix and its plan update together if the gate must be removed.
