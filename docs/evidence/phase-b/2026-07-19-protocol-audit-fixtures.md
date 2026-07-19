# Protocol audit and ETF fixture evidence

## Scope

Primary-source matrix and deterministic ETF golden vectors for the M1 subset.

## Environment

- Zig 0.16.0
- Fixture generator: Erlang/OTP 28 through Elixir 1.19.5

OTP 28 generated stable ETF vectors only. OTP 25–27 interoperability remains unverified.

## Commands

```sh
elixir scripts/interop/generate_etf_fixtures.exs
zig fmt --check build.zig src tests examples
zig build test-conformance
zig build test-all
```

## Result

The fixture manifest contains seven named vectors. Conformance wiring validates the three-column format, even-length hexadecimal data, and ETF version byte `131`.

## Sources

See `docs/protocol-sources.md` for official OTP 25–27 references.
