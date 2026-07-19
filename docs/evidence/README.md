# Verification Evidence

Evidence records support implementation and compatibility claims. Passing tests without preserved inputs or environment details is not sufficient for protocol, safety, or performance claims.

## Phases

- `phase-a/` — local logic, type/API contract, and compile-fail evidence.
- `phase-b/` — integration, wire fixtures, and real OTP interoperability.
- `phase-c/` — concurrency, network failure, liveness, boundedness, and performance stress.

## Required record fields

Each record identifies the commit, date, environment, commands, expected result, actual result, and related requirement or ADR. Packet captures and raw benchmark files must be referenced without embedding credentials or Erlang cookies.

A design document cannot cite a planned test as completed evidence.
