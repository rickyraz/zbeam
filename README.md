# zbeam

[![CI](https://github.com/rickyraz/zbeam/actions/workflows/ci.yml/badge.svg)](https://github.com/rickyraz/zbeam/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

> **Research scaffold — not a usable Erlang node.** zbeam currently builds on Zig 0.16.0, but EPMD, ETF, the distribution handshake, actors, and transport are not implemented yet.

zbeam explores a native Zig implementation of the Erlang Distribution Protocol (EDP v5/v6). The long-term goal is for a standalone Zig process to participate in an Erlang/OTP cluster as a distribution peer, without a NIF, port driver, or OTP patch.

## Project rationale

The narrow hypothesis is that some workloads need both:

- explicit, non-tracing-GC memory management for native, latency-sensitive state; and
- individual BEAM-visible identities with link/monitor semantics, rather than one multiplexed byte-stream endpoint.

Process isolation alone is **not** the differentiator: Erlang ports already provide it. zbeam must prove that granular actor identity is useful enough to justify the much larger EDP implementation cost.

## Current status

| Area | Status |
|---|---|
| Zig 0.16.0 build and test layout | Scaffolded |
| Public package/module boundaries | Scaffolded |
| ETF codec | Not implemented |
| EPMD client | Not implemented |
| Distribution handshake | Not implemented |
| Distribution control messages | Not implemented |
| Actor runtime and mailbox | Not implemented |
| Demand-driven backpressure | Design only |
| Arena-backed ownership transfer | Design only |
| OTP compatibility | Target only; not verified |

The v0.5 document is a **design target**, not implementation evidence. See [Implementation Status](docs/implementation-status.md) before relying on any specification claim.

## Build

Requirements:

- Zig 0.16.0 or newer
- Git
- Erlang/OTP 25–27 later, when protocol conformance work begins

```sh
zig build
zig build test-all
zig build run
```

The current tests only verify repository wiring and importability. A green build does **not** establish OTP or wire-protocol conformance.

## Documentation

- [v0.5.0 draft specification](specs/zbeam-v0.5.0.md) — latest design target
- [Implementation status](docs/implementation-status.md) — spec-to-code truth table
- [Roadmap](ROADMAP.md) — evidence-first implementation order
- [Research backlog](docs/research-needed.md) — unresolved safety and runtime risks
- [Protocol source matrix](docs/protocol-sources.md) — primary OTP references and initial wire subset
- [Architecture decisions](docs/adr/README.md)
- [Verification evidence](docs/evidence/README.md)

Historical specifications remain under [`specs/`](specs/). They are not current contracts.

## Battery-pack architecture

zbeam ships as one repository package with independently importable modules:

| Import | Responsibility | Allowed zbeam dependencies |
|---|---|---|
| `zbeam-etf` | ETF terms and wire codec | None |
| `zbeam-protocol` | Handshake, control, identity, and frame semantics | `zbeam-etf` |
| `zbeam-transport` | Socket and framed I/O | `zbeam-protocol`, `zbeam-etf` |
| `zbeam-actor` | Mailbox and local actor contracts | None |
| `zbeam-runtime` | Runtime composition and lifecycle | All narrower batteries |
| `zbeam` | Convenience re-export | All batteries; no behavior |

```zig
const zbeam = @import("zbeam");          // complete convenience surface
const etf = @import("zbeam-etf");       // standalone battery
const protocol = @import("zbeam-protocol");
```

Tools and OTP interoperability suites are repository build/test assets, not runtime packages. See [ADR 0001](docs/adr/0001-battery-pack-module-boundaries.md).

## Design boundaries

- zbeam is a separate OS process and distribution peer, never an in-process NIF.
- Transport ownership must remain separate from actor behavior.
- No transport read may occur without positive effective demand.
- Raw slices and pointers must not escape actor or asynchronous boundaries without explicit ownership.
- Zero-copy, performance, fault-isolation, and OTP-compatibility claims require reproducible evidence.
- A process boundary isolates zbeam from the BEAM VM; it does not isolate unsafe actors from one another inside one zbeam process.

## Roadmap in one line

First make **one real actor** interoperable with OTP and compare it with one Port; only then add local multi-actor semantics, ownership-transfer optimization, or io_uring.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md). The most useful early contributions are small protocol fixtures, OTP black-box tests, and corrections backed by primary sources.

## Security

This repository is pre-alpha research software. Do not expose it to untrusted networks. See [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)
