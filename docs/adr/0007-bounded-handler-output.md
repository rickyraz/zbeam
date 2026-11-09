# ADR 0007 — Bounded 64 KiB output for compiled handlers

**Status:** proposed; no implementation claim.
**Date:** 2026-11-09.
**Relation:** supersedes only the output rules of [ADR 0006](0006-compiled-binary-handler.md): the 32-byte output buffer, the `*[32]u8` handler parameter and `Result.output_len`. ADR 0006's other decisions remain in force: one stateless build-time function, copied input of at most 1 MiB, separate `call` and `hash` profiles, no replay and process-wide panic risk. The SHA-256 `TaskRuntime`, `serve-worker` and `serve-workers` contracts are unchanged.

## Context

A 32-byte result fits hashes and small identifiers, but not most transforms, encodings or structured replies. Output must stay bounded, owned by the runtime and allocation-free at completion, as in ADR 0004. Three limits interact:

- completion results are stored inline per ticket until collected, and a ticket is reused immediately after collection;
- replies are encoded into a 16 KiB stack scratch buffer, and the generic ETF encoder needs several times the payload size in that buffer;
- `Result` is returned by value, and changing `Outcome` would break exhaustive switches in existing SHA-256 users.

## Decision

- **Limit.** `TaskRuntime.max_output` is 64 KiB. A larger output is out of scope for this decision.
- **Handler.** `Handler` becomes `*const fn (input: []const u8, output: []u8) error{HandlerFailed}!usize`. `output` is a runtime-owned buffer of exactly `max_output` bytes, zeroed before every call and borrowed only during the call. Returning `error.HandlerFailed` or a length above `output.len` yields `handler_failed` and retires that actor, as before.
- **Storage.** When a handler is configured, the runtime allocates at creation one output buffer per completion ticket (2 actors × 5 tickets) and one collector buffer: 11 × 64 KiB = 704 KiB. Completion writes no new allocation. SHA-256 mode allocates nothing extra.
- **Results.** `Result.output_len` is replaced by `Result.output: []const u8`. For a custom success, collection copies the ticket's used prefix into the collector buffer and frees the ticket; `output` borrows the collector buffer until the next `nextResult` call or `deinit`, relying on the existing single-collector rule. A custom success keeps the `.digest` tag with a zeroed digest, so `Outcome` is unchanged. SHA-256 results keep `outcome.digest` and an empty `output`.
- **Wire.** The `call` profile replies `{Ref, {ok, Binary}}` with 0–65 536 bytes. The encoder builds the reply with an empty binary in the existing 16 KiB scratch, then patches the binary and frame lengths and writes the header followed by the borrowed output bytes, so no payload-sized scratch is needed. An output above `max_output` remains a fatal invariant error.
- **Owner.** `TwoWorkerOwner.call/3` accepts replies of 0–65 536 bytes.

## Consequences

Custom-mode memory adds 704 KiB of fixed output storage to the existing bound of ten 1 MiB input copies. Each call zeroes 64 KiB and each collection copies at most 64 KiB. Existing custom handlers must change their output parameter from `*[32]u8` to `[]u8`; the bundled example, the panic fixture and tests change with the runtime. Handlers that relied on a 32-byte failure boundary, including the example's deliberate failure for inputs above 32 bytes, now fail above 64 KiB instead.

Outputs above 64 KiB, streaming results, stateful handlers, dynamic plugins, TLS and production readiness remain separate decisions.

## Verification and rollout

1. Record this proposal without implementation claims.
2. Add the header-plus-payload binary reply: compare it byte-for-byte with the generic encoder for 0, 1, 32, 33, 4 096 and 65 536 bytes, reject 65 537, and add an OTP-generated vector longer than 32 bytes checked on OTP 25/26/27.
3. Switch the runtime, session, owner, example and tests together: 0, 32, 33 and 65 536-byte outputs; 65 537 returned length and handler errors; zeroed buffers; collector lifetime across ticket reuse; unchanged SHA-256 results; live OTP 25/26/27 replies of 65 536 bytes; and the Elixir owner suites.
4. Check actual merged-master CI and job markers, then decide acceptance.

Each step stays within 400 changed lines with its tests and evidence, and reverts independently. Step 3 reverts together with its callers; step 2 alone changes no observable behavior.
