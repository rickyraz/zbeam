# Implementation Status

**Last reviewed:** 2026-07-12  
**Code version:** 0.0.1 pre-alpha  
**Design target:** v0.5.0 draft

This file is the source of truth when code and specifications differ.

## Implemented repository infrastructure

- Zig 0.16.0 package and executable targets
- public module boundaries for actor, ETF, protocol, runtime, and transport
- separate unit, integration, conformance, and stress build steps
- research labs, benchmark directories, and evidence directories

## Unimplemented subsystems

No production behavior described by the v0.5 draft is implemented. In particular, the repository has no working:

- ETF encoder or decoder;
- EPMD client;
- Erlang distribution handshake;
- distribution framing, control messages, fragmentation, or heartbeats;
- actor scheduler, mailbox, registry, links, or monitors;
- demand signal, transport arena, `BufferHandle`, or io_uring backend;
- OTP interoperability or crash-isolation conformance harness.

## Specification interpretation

The specifications contain pseudocode and proposed invariants. Words such as “implemented,” “fixed,” or “conformance-tested” describe the intended revision relative to earlier design documents; they do **not** describe this repository's current code.

A feature becomes implemented only when all of the following exist in the same change:

1. code under the correct `src/zbeam/*` boundary;
2. a runnable test at the required level;
3. verification evidence under `docs/evidence/`;
4. an updated row in this file.

## Compatibility

OTP 25, 26, and 27 are design targets. No compatibility claim is currently made.
