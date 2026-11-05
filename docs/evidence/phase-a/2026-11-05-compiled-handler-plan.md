# Compiled handler: design inspection

**Candidate basis:** owner stop candidate `2854b6ddbefadb0c479e88691dd1dc2a753e5b52`, pressure change merged as `911cae5278efac509ba43009bed3cfdccf6e9f80`. Inspected 2026-11-05 on Linux WSL2 x86-64; Zig 0.17.0. This is a design record, not implementation evidence.

`task_runtime.zig` owns two tasks and invokes SHA-256 after claiming an owned input. `task_admission.zig` holds five terminal records per actor with an inline 32-byte digest. `wire_route.zig` recognizes only `hash`, `wire_session.zig` encodes the fixed digest, and `wire_connection.zig` joins operations and drains old completions before freeing peer state. `wire_service.zig` creates a private runtime; `node.zig` composes it under the existing dependency DAG. `src/main.zig` owns loopback registration and EPMD-loss cancellation. The M2c owner is specifically SHA-256-oriented.

[ADR 0006](../../adr/0006-compiled-binary-handler.md) proposes a separate build-selected stateless function, input borrowing and zero-initialized inline output with an explicit 0–32-byte length, plus a distinct `call` wire command. The default `hash` mode and old APIs remain in place. Each later unit must carry tests and lifecycle evidence; no network command is enabled by this record.

**Verification:** source inspection only; no tests were run for this documentation-only unit. Existing M2c/pressure/stop evidence does not test compiled handlers. Roll back this ADR, index, backlog, spec and evidence entry together.
