# M2b connection fault checks — 2026-10-28

This internal-only unit tests launch failures, cancellation, partial frames,
read deadlines and failed/blocked writes. It corrects the connection loop to
preserve `Timeout` instead of replacing it with the reader's cancellation error
from the joined losing task. Only `ReadFailed` is unwrapped to its socket cause.
No public listener or OTP profile is enabled.

## Verification

Zig 0.17.0 on Linux/WSL, separate debug and safe caches:

- `zig build test-unit -Doptimize=<debug|safe> -j2 --summary all`: 15/15
  steps; 68/69 newly executed tests, one conditional skip each mode.
- `zig build test-all test-labs test-task-lifecycle -Doptimize=<debug|safe>
  -j2 --summary all`: 69/69 steps; 50/51 newly executed tests, one skip each;
  remaining tests were cached. The separate watchdog killed/reaped its spin
  child, and the local runtime example passed.
- Thirty fresh runtime-test launches per mode: each 65 passed, one spin skip.
- Injected reader startup failures and collector startup failure verify no
  reservations or accepted completions remain. Partial headers/payloads time
  out; malformed complete input fails closed. Failed and blocked output release
  credits after writer join. A paused handler and test barriers prove cancellation
  joins reader/collector before waiting for accepted work.
- The first two compile attempts exposed incorrect test-shim error and Future
  types. The third attempt demonstrated the real timeout-masking bug. All three
  logs are retained beside successful runs; the test was not weakened to pass.

## Limits and rollback

These are loopback streams and deterministic I/O shims, not OTP interop or an
OS-level OOM test. Cooperative drain can wait indefinitely for noncooperative
work; an external owner must kill/reap the process. Remove the added fault tests
and restore the read-error expression to roll back this unit; the latter
reintroduces timeout misreporting. Independent wire vectors, authenticated
service, EPMD lifecycle and real OTP matrix remain open.
