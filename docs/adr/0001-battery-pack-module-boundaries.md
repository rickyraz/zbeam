# ADR 0001 — Battery-Pack Module Boundaries

**Status:** Accepted  
**Date:** 2026-07-12

## Context

zbeam needs a standalone ETF codec, pure distribution semantics, optional transport, and an optional actor runtime. Splitting an unimplemented scaffold into repositories or separately versioned packages would add release coordination without reducing dependencies because the project currently has none.

## Decision

The repository remains one Zig package and exposes six import modules:

- `zbeam` — convenience umbrella;
- `zbeam-etf` — term and ETF wire representation;
- `zbeam-protocol` — pure distribution state and wire semantics;
- `zbeam-transport` — socket and framed I/O;
- `zbeam-actor` — local mailbox and actor contracts;
- `zbeam-runtime` — composition and lifecycle.

Allowed dependency direction:

```text
protocol  -> etf
transport -> protocol, etf
runtime   -> actor, transport, protocol, etf
```

`etf` and `actor` have no upstream zbeam dependencies. `transport` cannot depend on `actor` or `runtime`. The umbrella adds no behavior.

Tools remain executables under `tools/`. Fixtures and OTP compatibility suites remain verification assets under `fixtures/` and `tests/interop/`.

## Consequences

Applications can import the umbrella or a narrower battery without a repository split. Build wiring enforces the intended dependency graph before implementation begins. Additional module and release surfaces must be justified by a real consumer, distinct dependencies, or independent release cadence.

## Evidence

`zig build test-unit` compiles every battery independently. `zig build test-integration` verifies all independent imports and the umbrella import.
