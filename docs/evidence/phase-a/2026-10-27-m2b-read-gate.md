# Internal pre-read gate — M2b prerequisite

An internal frame reservation combines the per-connection output credit and
atomic all-running-actor lease **before** calling the existing unbuffered
`readDemandedPacket`. If output or any actor is full, both reservations roll
back and no read or frame allocation occurs. It performs at most one frame read
per reservation. On read error/partial frame, the owner must join the reader,
release all reservations and terminate that connection; no partial stream resume.
Controls and unknown targets retain their credit until output finishes or drops.

After a successful read, correlation validation precedes the selected actor's
copy/queue transfer. A successful send binds the unique request ID without an
intervening cancellation point; output stays reserved through write/drop. A
failed validation, allocation or insertion releases both resources. The owner
serializes operations on the output table, joins any reader before touching its
frame, frees the returned frame bytes, and joins all API users before deinit.
These functions are internal and not yet wired to a network service.

Three tests use a counted unbuffered reader: full output or actor capacity yields
zero read calls and allocations; one read preserves the next frame and transfers
one request; truncated read and untrusted correlation release capacity. The
transfer test uses a minimal framed marker to exercise ownership, **not** a
validated distribution payload or OTP exchange. Actual socket integration,
encoded-byte limits, completion collection, epoch teardown, monitor ordering,
wire schema approval and OTP conformance remain open.

Linux x86-64 WSL2/Zig 0.17.0: debug/safe core/labs/lifecycle each completed
69/69 steps, 97/99 newly executed tests passed with two conditional skips and
unaffected runs cached; standalone watchdog/example passed. Thirty fresh runtime
launches per mode: 46 passed, one conditional skip per launch. The initial debug
build failed on an unused mutable test reader; it was replaced by an actual
`tryRead` path to assert the zero-read behavior. Original and final logs retained.

Rollback removes `wire_gate.zig`, its test-only import and these records; no
public task API, socket profile or protocol/transport code changes.
