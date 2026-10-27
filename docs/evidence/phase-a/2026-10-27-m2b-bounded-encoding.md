# Fixed-scratch reply encoding — M2b prerequisite

The internal `wire_encode.zig` builds only the candidate bounded replies and
monitor exits using a caller-owned **16 KiB** scratch array and
`FixedBufferAllocator`. That bound includes intermediate ETF encoding and the
returned frame, not provider resources, input/decoded terms, monitor table,
network buffers or RSS. The returned slice borrows scratch until the writer
finishes or drops it; it must not be reused during an in-flight write.

Tests round-trip exact reply PID, reference, digest/error and monitor-exit
fields with the project's codec; both monitor target/reason forms and maximum
255-byte atoms are exercised. Oversized encoder input exhausts the fixed scratch
instead of allocating elsewhere; invalid references fail. This is not an
independent OTP vector, a writer/timeout test, a fully derived upper bound for
all future schemas, or evidence of a network profile. Allocation/encoding
failure must close/drop the connection without claiming delivery when integrated.

Linux x86-64 WSL2/Zig 0.17.0: core/labs/lifecycle debug and safe each completed
69/69 steps, 100/102 newly executed tests passed with two conditional skips and
unaffected tests cached; watchdog/example passed. Thirty fresh runtime binary
launches per mode each had 49 passes and one conditional skip. Raw logs are
retained adjacent. No socket, CLI, production OTP flag or public export changes.

Rollback removes the fixed encoder, its test-only import and this evidence. The
[wire ADR](../../adr/0005-two-worker-wire-profile.md), connection epoch, control
ordering, independently generated conformance vectors and real OTP acceptance
remain open.
