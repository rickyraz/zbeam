# Split reply writes and Nagle latency

- **Date:** 2026-11-09 UTC.
- **Base:** master `e7e7b22b60bc397e64ba24266256c936b00833a9`.
- **Introduced by:** PR #66 (`writePacketParts`), merged as `e00cd9a`.

## Failure

A 20-second local run of the owner soak harness (added in the following change)
with two callers per actor showed the custom profile at **p50 43 009 µs and
70 successful calls per second**, against p50 926 µs for the SHA-256 profile
in the same environment. CI did not fail, because each test's timeout is
several seconds.

`writePacketParts` wrote the reply header and the output bytes with two
`writeAll` calls. The connection writer is unbuffered, so each became a separate
`sendmsg`. With the header segment still unacknowledged, Nagle's algorithm held
the small tail until the peer's delayed ACK, about 40 ms on Linux. zbeam does not
set `TCP_NODELAY`. Only custom `call` replies used the split path.

## Fix

`writePacketParts` now passes both parts to one `writeVecAll`, which the
unbuffered stream writer sends as a single vectored `sendmsg`. `writePacket`
uses the same path with an empty tail, so every frame still uses one call.

## Tests

- A counting writer with no buffer receives exactly one `drain` call carrying
  all seven bytes of a split frame; the previous two-`writeAll` form makes two.
- The same 20-second custom soak afterwards measured **p50 770 µs, p99 2 715 µs,
  max 4 834 µs and 2 063 successful calls per second**, with exact results and
  no owner restart.

## Local results

Linux WSL2 x86-64, Zig 0.17.0, Elixir 1.20.4 / OTP 29.1.1, Docker.

- `zig fmt --check build.zig src tests examples` passed.
- `zig build test-all test-labs test-task-lifecycle test-worker-recovery
  -Doptimize={debug,safe} -j2 --summary all` passed 77/77 steps in each mode
  (debug 55/57 and safe 150/154 newly executed tests; only watchdog-gated cases
  skipped; other steps cached).
- `zig build test-interop-docker -Doptimize=safe` passed all three pinned OTP
  targets, none missing.
- Logs: `~/.local/state/zbeam-maintenance/2026-11-09-m3/soak-local-custom-20s*.log`
  and `vectored-*.log`.

## Limits

A multi-segment reply's final partial segment can still wait for an ACK under
Nagle; the 64 KiB samples above did not show a 40 ms stall, but `TCP_NODELAY`
is still unset. The numbers come from one WSL2 host and are not a latency bound.

**Rollback:** revert this change only together with a replacement for split
writes; reverting alone restores the 40 ms stall.
