# zbeam

[![CI](https://github.com/rickyraz/zbeam/actions/workflows/ci.yml/badge.svg)](https://github.com/rickyraz/zbeam/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

> **A bounded, single-actor Erlang Distribution peer in Zig.**

zbeam implements a development MVP: a separate Zig process registers through EPMD, authenticates with OTP, exposes one registered echo actor, and supports repeated messages and sequential reconnects. Both handshake directions are verified against real OTP 25, 26 and 27.

**Not a production Erlang node.** Compatibility is limited to the [MVP wire subset](docs/mvp.md). Arbitrary ETF terms, RPC, process links/monitors, distributed registry semantics and the full v0.5 runtime are not implemented.

## Purpose

NIFs execute native code within the BEAM VM. Ports already provide a separate-process boundary. zbeam explores whether distribution-addressable native actors justify the additional protocol and lifecycle complexity; process isolation alone is not its differentiator.

The current benchmark includes negative results. It does not establish a performance advantage over Ports.

## Current status

| Area | Status |
|---|---|
| Zig 0.16.0 and battery dependency graph | Implemented and tested |
| ETF | Bounded owned subset, including aggregate allocation limits |
| EPMD and handshake | Registration/lookup; both handshake roles verified on OTP 25–27 |
| Distribution | Pass-through framing, tick echo, REG_SEND/SEND subset |
| Service lifecycle | One synchronous actor; repeated messages; sequential peer recovery |
| Backpressure | Demand-gated unbuffered reads; TCP saturation/resume evidence |
| Local actor primitives | Bounded mailbox, logical receive ownership, registry and termination |
| Process-loss isolation | SIGKILL/nodedown tests with surviving OTP VM and local process |
| Arena-backed ownership and io_uring | Not implemented; research only |

[Implementation Status](docs/implementation-status.md) is the source of truth. The v0.5 specification describes a broader design, not shipped behavior.

## Build and verify

Requirements: Zig 0.16.0 and Git. Interoperability checks additionally require Erlang/EPMD; the pinned-container runner requires Linux and Docker.

```sh
zig build
zig build test-all                            # deterministic, no external EPMD required
zig build test-all -Doptimize=ReleaseSafe
zig build test-interop-docker                 # all OTP 25/26/27 targets; pinned images
```

Native OTP installations can use `OTP_ERL_25`, `OTP_ERL_26` and `OTP_ERL_27` with `ZBEAM_REQUIRE_ALL_OTP=1 zig build test-interop`. Missing targets are not passes, and incorrectly labeled versions fail.

## Run the echo service

```sh
epmd -daemon
./zig-out/bin/zbeam serve zbeam_echo development_cookie
```

In another terminal:

```sh
erl +S 2:2 -noshell -name client@127.0.0.1 -setcookie development_cookie -eval '
  N = list_to_atom("zbeam_echo@127.0.0.1"),
  true = net_kernel:connect_node(N),
  {echo, N} ! hello,
  receive hello -> io:format("echo passed~n") after 3000 -> halt(1) end,
  halt().'
```

The service binds IPv4 loopback and handles one active peer at a time. `echo` provides a bounded one-shot variant; `probe` initiates a request to a real OTP echo actor. See [MVP usage and contracts](docs/mvp.md).

Cookies in arguments are visible in process listings. There are no network deadlines or TLS integration; do not expose this development service to untrusted peers.

## Battery-pack architecture

| Import | Responsibility | Allowed zbeam dependencies |
|---|---|---|
| `zbeam-etf` | Owned terms and ETF codec | None |
| `zbeam-protocol` | Pure wire and handshake semantics | `zbeam-etf` |
| `zbeam-transport` | EPMD, handshake and framed I/O | Protocol, ETF |
| `zbeam-actor` | Bounded mailbox and demand primitives | None |
| `zbeam-runtime` | Service composition and local registry | All narrower batteries |
| `zbeam` | Behavior-free convenience exports | All batteries |

```zig
const zbeam = @import("zbeam");
const etf = @import("zbeam-etf");
```

Transport never imports actor/runtime. The actor-facing dispatcher reserves demand before reading and never prefetches another frame. Decoded bytes are owned copies; no zero-copy claim is made. The OS process boundary does not isolate actors from each other inside zbeam.

## Documentation

- [MVP scope, commands, limits and remaining work](docs/mvp.md)
- [Implementation status](docs/implementation-status.md)
- [Roadmap](ROADMAP.md) and [research/risk backlog](docs/research-needed.md)
- [Protocol primary sources](docs/protocol-sources.md)
- [Architecture decisions](docs/adr/README.md)
- [Verification evidence](docs/evidence/README.md)
- [Port comparison](benchmarks/README.md)
- [v0.5.0 draft](specs/zbeam-v0.5.0.md), a design target with unimplemented pseudocode

Contribution requirements are in [CONTRIBUTING.md](CONTRIBUTING.md). Security limits are in [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)
