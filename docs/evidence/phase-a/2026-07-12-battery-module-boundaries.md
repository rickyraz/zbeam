# Battery-module boundary verification

## Scope

Build-level module independence and allowed dependency direction from ADR 0001.

## Implemented structure

- `zbeam-etf` and `zbeam-actor` have no zbeam imports.
- `zbeam-protocol` may import only `zbeam-etf`.
- `zbeam-transport` may import `zbeam-protocol` and `zbeam-etf`.
- `zbeam-runtime` composes actor, transport, protocol, and ETF batteries.
- `zbeam` re-exports modules without behavior.
- tools and interoperability assets remain outside runtime package code.

## Verification

```sh
zig fmt --check build.zig src tests examples
zig build
zig build test-unit
zig build test-integration
zig build test-conformance
zig build test-stress
zig build test-all
```

`test-unit` compiles every battery as a root module. `test-integration` imports every battery independently and through the umbrella.
