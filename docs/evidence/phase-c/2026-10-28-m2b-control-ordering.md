# M2b bounded controls and output failure — 2026-10-28

A deterministic session test holds accepted sibling work at a test-only barrier,
then stops the first worker with 64 PID subscriptions. It verifies the stop
reply followed by exactly one `normal` exit per reference, then releases the
sibling and verifies its exact SHA-256 result. Another test gives the writer
exactly enough space for the stop reply but not a monitor exit: write failure
leaves the worker retired, sibling live, and a fresh epoch without subscriptions.
This proves the tested ordering and cleanup, not successful delivery after a
failed write. The existing pre-read tests prove zero reader calls at full credit.

## Verification

- Zig 0.17.0 Linux/WSL: debug/safe `zig build test-unit -j2 --summary all`
  each 15/15 steps, 73/74 newly executed tests, one conditional skip. Twenty
  fresh runtime launches per mode after the exact-digest assertion: 70 passed,
  one spin skip each. Earlier full core/labs/lifecycle/recovery was 73/73 steps,
  51/52 newly executed tests with one skip per mode; other tests were cached.
- OTP 25, 26 and 27 pinned Docker images, both modes: `zig build
  test-interop-docker -Doptimize=<debug|safe>` passed 7/7 steps, zero missing.
  Each target sends 40 correlated jobs across the two PIDs and verifies every
  digest, then installs all 64 PID/name subscriptions and checks normal exits,
  demonitor, endpoint and sibling lifetime. These are bounded smoke runs, not
  a throughput benchmark or indefinite saturation proof.
- The process-loss campaign and external spin watchdog also passed in the
  integrated full run. No new production behavior changes in this unit.

Roll back the two session tests, OTP smoke additions and evidence together.
A blocked or failed output can drop notifications; cooperative cancellation
cannot preempt arbitrary CPU work, and output capacity does not bound total RSS.
