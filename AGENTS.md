# AGENTS.md

## Persona
Deterministic, policy-first engineering assistant.
Prioritize strict module boundaries, protocol conformance evidence, and auditable changes.

## Project Structure
- `src/root.zig` → public package surface (`@import("zbeam")`)
- `src/main.zig` → executable entrypoint
- `src/zbeam/transport` → transport layer
- `src/zbeam/actor` → actor/mailbox layer
- `src/zbeam/etf` → ETF encoding/decoding layer
- `src/zbeam/protocol` → EPMD/handshake/distribution protocol layer
- `src/zbeam/runtime` → runtime core (scheduler/demand/lifecycle)
- `src/experimental/typestate` → non-production type-state experiments
- `tests/integration` → integration scenarios
- `tests/conformance` → protocol/wire conformance checks
- `tests/stress` → liveness/backpressure/race stress tests
- `examples` → runnable usage examples
- `labs/*` → curriculum research artifacts (numbered)
- `benchmarks/*` → performance experiments
- `docs/adr` → architecture decision records
- `docs/evidence/phase-{a,b,c}` → verification evidence by phase
- `docs/research-needed.md` → active research/risk backlog
- `specs/zbeam-v0.3.0.md` → primary technical spec

## Reading Order (Before Major Changes)
1. `AGENTS.md`
2. `specs/zbeam-v0.3.0.md`
3. `docs/research-needed.md`
4. `docs-id/kurikulum.md`
5. touched modules under `src/zbeam/*`

## Environment
Required:
- Zig 0.16.0+ (`std.Io` interface mandatory)
- Git

Recommended:
- Erlang/OTP 25, 26, 27
- Linux for `io_uring` research path

Core local checks:

```bash
zig fmt build.zig $(find src tests examples -name '*.zig' -type f)
zig build
zig build test-unit
zig build test-integration
zig build test-conformance
zig build test-stress
zig build test-all
```

## Core Rules
- Every behavior change MUST include tests in the same change.
- Preserve transport/actor separation (v0.3.0 invariant).
- Demand-based receive contract is mandatory: no transport read without positive effective demand.
- Mailbox operations must remain thread-safe and auditable.
- `BufferHandle` lifetime escapes must use explicit ownership strategy.
- Panics/errors must not cross node boundary uncaught.
- Protocol-visible changes MUST keep OTP compatibility target explicit.

## DO NOT
- Re-introduce unbounded mailbox buffering that hides TCP backpressure.
- Pass raw slices/pointers across actor or async boundaries without ownership discipline.
- Mix transport ownership logic into actor business logic.
- Claim zero-copy behavior without evidence.
- Mix unrelated concerns in one commit.

## Testing (Required Before Commit)
- Level A (logic/contract): `zig build test-unit`
- Level B (integration/protocol): `zig build test-integration` + `zig build test-conformance`
- Level C (runtime/network stress): `zig build test-stress`

For protocol contract changes, include conformance tests and update evidence.

## Docs Sync
When changing contract/lifecycle/boundaries:
- update relevant section in `specs/zbeam-v0.3.0.md`,
- update `docs/research-needed.md` when adding risk/open question,
- record verification summary in `docs/evidence/phase-*/`.

## Commit Rules
Commit only after relevant verification completes.
One commit = one coherent engineering concern.

Format:
```
<type>(<scope>): <imperative present-tense description>

- what changed
- why (if non-trivial)

Test status: <passed / skipped with reason>
Verification: <commands + environment + key evidence>
```

Types:
`feat` `fix` `refactor` `test` `docs` `chore` `perf` `spec`

Scopes:
`transport` `actor` `etf` `protocol` `runtime` `conformance` `build` `docs` `lab`
