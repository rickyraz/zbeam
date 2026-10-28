# M2b internal service owner — 2026-10-28

The internal owner creates both fixed tasks before publishing two distinct full
wire PIDs, authenticates one supplied stream, retains identities across
sequential peers and joins tasks before deinit. It owns the runtime exclusively;
no listener, EPMD integration, CLI or public API is enabled in this unit.

## Verification

Zig 0.17.0, Linux/WSL, separate debug/safe caches:

- Focused `zig build test-unit -Doptimize=<debug|safe> -j2 --summary all`:
  15/15 steps, 71/72 newly executed checks, one conditional skip each mode.
- Twenty fresh runtime-test launches per mode after adding the bad-cookie case:
  each 68 passed, one spin skip. Independent initiator/acceptor handshakes reject
  a wrong cookie; two subsequent authenticated connections discover the same
  two distinct PIDs. These are both zbeam implementations, not OTP evidence.
- Allocator failure and injected first/second task-start failures publish no
  owner; an already started task is joined and counted allocations are freed.
- Before the final bad-cookie test was added, debug/safe core, labs and lifecycle
  each passed 69/69 steps, 122/124 newly executed checks with two skips; the
  separate watchdog killed/reaped its child and the example passed. Those logs
  do not cover the subsequently added test.

## Limits and rollback

The caller serializes `servePeer`, joins it before deinit and keeps configuration
and the I/O provider alive. Epoch exhaustion fails closed. Disconnect drain and
shutdown remain cooperative; a noncooperative task requires external kill.
Remove the internal service owner, its tests and the test import to roll back
without changing M1. Actual OTP, listener, registration loss, process recovery
and independent wire fixtures are still required.
