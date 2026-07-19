# Implementation Status

**Last reviewed:** 2026-07-12  
**Code version:** 0.0.1 pre-alpha  
**Design target:** v0.5.0 draft

This file is the source of truth when code and specifications differ.

## Implemented repository infrastructure

- Zig 0.16.0 package and executable targets
- independently importable `zbeam-etf`, `zbeam-protocol`, `zbeam-transport`, `zbeam-actor`, and `zbeam-runtime` batteries
- a behavior-free `zbeam` convenience umbrella
- build-declared dependency direction matching ADR 0001
- bounded owned ETF codec for integer, UTF-8 atom, tuple, binary, proper byte/list forms, nil, and `NEW_PID_EXT`
- EPMD ALIVE2 registration and PORT_PLEASE2 lookup with registration-socket lifetime ownership
- OTP 23+ initiating and accepting handshake codec/FSM with cookie challenge verification
- four-byte pass-through distribution framing, ticks, `REG_SEND` routing, `SEND` replies, and a one-shot registered echo peer
- bounded `std.Io.Queue` mailbox with one logical consumer, atomic demand credits, named registry, and explicit termination
- reproducible OTP matrix orchestration and a local Erlang Port latency baseline
- separate unit, integration, conformance, and stress build steps
- research labs, benchmark directories, and evidence directories

## Unimplemented subsystems

No production behavior described by the v0.5 draft is implemented. In particular, the repository has no working:

- ETF tags outside the documented initial subset;
- EPMD operations outside registration and node lookup;
- handshake variants outside the OTP 23+ format and target-version black-box verification;
- distribution headers with atom caches, fragmentation, heartbeats beyond tick echo, or control operations outside initial send routing;
- actor task scheduler, distributed registry semantics, links, or monitors;
- transport demand gating, demand liveness diagnostics, transport arena, `BufferHandle`, or io_uring backend;
- OTP interoperability or crash-isolation conformance harness.

## Specification interpretation

The specifications contain pseudocode and proposed invariants. Words such as “implemented,” “fixed,” or “conformance-tested” describe the intended revision relative to earlier design documents; they do **not** describe this repository's current code.

A feature becomes implemented only when all of the following exist in the same change:

1. code under the correct `src/zbeam/*` boundary;
2. a runnable test at the required level;
3. verification evidence under `docs/evidence/`;
4. an updated row in this file.

## Structural boundaries

The module graph is implemented as build wiring, not subsystem behavior:

```text
protocol  -> etf
transport -> protocol, etf
runtime   -> actor, transport, protocol, etf
```

Tools and interoperability suites remain repository assets rather than consumable packages. Physical package or repository splits require a real standalone consumer or distinct dependency/release requirements.

## Compatibility

OTP 25, 26, and 27 are design targets. No compatibility claim is currently made.
