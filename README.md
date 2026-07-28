# zbeam

[![CI](https://github.com/rickyraz/zbeam/actions/workflows/ci.yml/badge.svg)](https://github.com/rickyraz/zbeam/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

> **BEAM-compatible nodes in Zig.**

zbeam is a pre-alpha implementation of the Erlang Distribution Protocol in Zig.

Its long-term goal is to let a standalone Zig process participate in an Erlang/OTP cluster as a distribution peer—with its own node identity and BEAM-visible processes—without running as a NIF, port driver, or patched OTP runtime.

> **Not a production Erlang node.**  
> The repository currently implements a bounded ETF, EPMD, handshake, distribution framing, and echo path. Broad OTP compatibility, protocol conformance, and production safety remain unverified.

## Why zbeam?

Native code can already be integrated with Erlang through NIFs and Ports:

- NIFs provide close integration but execute inside the BEAM VM.
- Ports provide process isolation but expose one multiplexed byte-stream endpoint.

zbeam explores a narrower hypothesis:

> Can a separate native process combine explicit memory management with granular BEAM-visible identities, messaging, links, and monitors?

Process isolation alone is not the differentiator—Ports already provide it. zbeam must demonstrate that native processes addressable through Erlang Distribution are useful enough to justify the implementation and verification cost of EDP.

## Current status

| Area | Status |
|---|---|
| Zig 0.16.0 build and test layout | Scaffolded |
| Public package boundaries | Scaffolded |
| ETF codec | Initial bounded subset |
| EPMD client | Registration and lookup implemented |
| Distribution handshake | Initiator and acceptor implemented; OTP matrix pending |
| Distribution framing | Ticks, `REG_SEND`, `SEND`, and one-shot echo implemented |
| Local actor subsystem | Bounded mailbox, registry, ownership, and lifecycle implemented |
| Demand-driven backpressure | Atomic credit primitive implemented; transport gating pending |
| Arena-backed ownership transfer | Design only |
| OTP compatibility | Target only; not verified |

The v0.5 specification is a **design target**, not evidence that every described feature exists.

See [Implementation Status](docs/implementation-status.md) for the current spec-to-code truth table.

## Build

### Requirements

- Zig 0.16.0 or newer
- Git
- Erlang/OTP 25–27 for interoperability testing

```sh
zig build
zig build test-all
zig build test-interop # configured OTP matrix; unavailable versions are skipped
zig build run
```

A one-shot development echo peer requires a local EPMD instance:

```sh
epmd -daemon
zig build
./zig-out/bin/zbeam echo zbeam_echo cookie
```

The cookie is visible in the process list; use this command only for local development.

## Documentation

- [Implementation status](docs/implementation-status.md) — source of truth for implemented behavior
- [v0.5.0 draft specification](specs/zbeam-v0.5.0.md) — design target
- [Roadmap](ROADMAP.md) — evidence-first implementation order
- [Research backlog](docs/research-needed.md) — unresolved safety and runtime risks
- [Protocol source matrix](docs/protocol-sources.md) — primary OTP references and initial wire subset
- [Architecture decisions](docs/adr/README.md)
- [Verification evidence](docs/evidence/README.md)

Historical specifications under [`specs/`](specs/) are not current contracts.

## Battery-pack architecture

zbeam exposes independently importable modules:

| Import | Responsibility | Allowed zbeam dependencies |
|---|---|---|
| `zbeam-etf` | ETF terms and wire codec | None |
| `zbeam-protocol` | Handshake, control, identity, and frame semantics | `zbeam-etf` |
| `zbeam-transport` | Socket and framed I/O | `zbeam-protocol`, `zbeam-etf` |
| `zbeam-actor` | Mailbox and local actor contracts | None |
| `zbeam-runtime` | Runtime composition and lifecycle | All narrower batteries |
| `zbeam` | Convenience re-export | All batteries; no behavior |

```zig
const zbeam = @import("zbeam");
const etf = @import("zbeam-etf");
const protocol = @import("zbeam-protocol");
```

Tools and OTP interoperability suites are repository build/test assets, not runtime packages. See [ADR 0001](docs/adr/0001-battery-pack-module-boundaries.md).

## Design boundaries

- zbeam is a separate OS process and distribution peer, never an in-process NIF.
- Transport ownership remains separate from actor behavior.
- No transport read may occur without positive effective demand.
- Raw slices and pointers do not escape actor or asynchronous boundaries without explicit ownership.
- Zero-copy, performance, fault-isolation, and OTP-compatibility claims require reproducible evidence.
- A process boundary isolates zbeam from the BEAM VM; it does not isolate unsafe actors from one another inside one zbeam process.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md). Useful early contributions include protocol fixtures, OTP black-box tests, and corrections backed by primary sources.

## Security

This repository is pre-alpha research software. Do not expose it to untrusted networks. See [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)
