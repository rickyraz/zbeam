# ADR 0006 — Compiled stateless binary handlers

**Status:** proposed; no implementation or compatibility claim.
**Date:** 2026-11-05.
**Relation:** additive to ADR 0001, ADR 0004 and ADR 0005. The default `TaskRuntime`, `serve-worker` and `serve-workers` SHA-256 contracts remain unchanged. ADR 0004's exclusion of general stateful handlers remains in force.

## Context

The accepted two-worker service is useful but hardcodes SHA-256. A separate-process executable should be able to compile in a small Zig function without loading plugins or passing unowned data across tasks. Arbitrary state, allocation, cancellation and output lifetimes cannot be inferred from a function pointer.

## Decision

Add an explicitly selected stateless handler mode, not a dynamic plugin or general actor scheduler:

- The executable supplies one Zig function at build time. The same function may run concurrently in both fixed actors; it must be thread-safe and must not create unmanaged tasks or retain either argument.
- The runtime owns and copies each admitted input, at most 1 MiB. The function borrows that input only until it returns. It receives a zero-initialized runtime-owned 32-byte output buffer and returns a length from 0 to 32, or `error.HandlerFailed`; oversized lengths are handler failures. No input/output pointer or slice escapes the call.
- Results and lengths remain inline under the existing five completion-held tickets per actor; the existing `.digest` storage and 32-byte SHA-256 results remain compatible. A length field distinguishes the used prefix in custom mode. Completion collection returns the ticket, and cleanup retains its existing join and caller-quiescence barriers.
- A returned error retires only the affected actor and yields `handler_failed`, subject to process-wide fail-closed recovery on uncertain transport outcome. A panic, memory corruption or noncooperative handler can still kill or stall the whole native process. No replay or preemption is introduced.
- A separate custom executable command uses `{FromPid, Ref, {call, Binary}}` and `{Ref, {ok, Binary}}`, with the existing discovery, stop, monitor, peer, connection-epoch and demand rules. It rejects `hash` in custom mode. Existing `serve-workers` accepts `hash`, rejects `call`, and remains SHA-256. The profiles must not silently share a command with different meanings.
- The supplied example performs a non-SHA-256 byte operation and is callable from Elixir. The initial output limit is deliberately 32 bytes, not a general large-result API. No public change is implied for the M2c SHA-256 owner.

The input budget remains ten copied 1 MiB requests. The ten fixed completion buffers remain 32 bytes each; length metadata, allocator/provider state, caller binaries, decoded frames and task stacks are additional. This is not an RSS or fairness guarantee. Cookies, trusted-node and single-peer limitations remain unchanged.

## Verification and rollout

1. Specify the contract and rollback boundaries; do not claim implementation.
2. Implement the local callback and inline length accounting with tests for empty/max output, bad lengths, handled errors, sibling progress, startup/stop and bounded ownership. Keep SHA-256 regressions unchanged.
3. Add mode-specific routing and bounded binary encoding with malformed and boundary tests; prove the original profile rejects `call`.
4. Wire a separately built example executable and Elixir client; exercise both workers, zero/max lengths, rejected input, handler failure, stop, reconnect and sibling survival on actual OTP 25/26/27 and supported Elixir/OTP versions.
5. Run unit/integration/conformance/stress, lifecycle, recovery, old profiles and actual merged-master CI. Record cached work and skips. No production claim follows.

Keep behavior, tests and evidence together in independently reviewable units of at most 400 changed text lines. Revert each additive unit together with its tests and evidence; do not alter accepted ADR bodies, old commands, fixtures or research branches. Dynamic libraries, arbitrary user state/destructors, large output, allocator injection, TLS, native-host soak and exactly-once delivery remain separate work.
