# Internal reply-correlation credits — M2b prerequisite

This adds a fixed ten-entry, connection-scoped correlation table; it is not yet
connected to a socket, runtime collector or writer. It provides **item-count**
bounds, not a bound on encoded bytes, allocator transients or physical RSS.
The authenticated peer name is borrowed from the connection owner and must remain
live through writer/reader joins and table discard. No decoded frame slice is
retained: validated PID/reference node fields are canonicalized to that name.

Under a caller-owned connection mutex, `reserve` consumes a credit without
allocation before a potential read. `prepare` validates peer node/creation and
reference length before work acceptance; `bind` associates the unique local
request ID without allocating. The integration must hold the same gate across
admission and binding so a concurrent result collector cannot observe an
unbound accepted request. All IDs are nonzero and unique within the runtime.
Canceled/failed unaccepted work returns its credit. A matching epoch/ID moves a
pending result to writing; the credit remains held until explicit write/drop
completion, not just result collection. A stale/unknown completion cannot free
another slot. Discard requires joined reader/writer and drained old results.

Unit tests cover all ten credits and the writing hold, epoch mismatch, missing
IDs, peer/ref validation, canonical node ownership and cancellation/reuse. They
do not exercise a network reader, concurrent integration, output encoder/byte
bound, controls, stop/monitor ordering or actual epoch teardown. These remain
[ADR 0005](../../adr/0005-two-worker-wire-profile.md) gates.

On Linux x86-64 WSL2/Zig 0.17.0, debug/safe core/labs/lifecycle completed with
69/69 steps and 90/92 newly executed tests passed, two conditional skips per mode;
unaffected runs were cached. Standalone spin watchdog and local example passed.
Each runtime test binary was also launched 50 times per mode: 39 passed and one
conditional skip per launch. The first debug build failed because the test
constant `reference` shadowed a function parameter; the constant was renamed,
and that original diagnostic remains alongside the successful logs.

Rollback removes `wire_output.zig`, its test-only import and these records; no
public API, protocol, transport or socket behavior needs reverting.
