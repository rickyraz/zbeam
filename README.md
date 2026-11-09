# zbeam

[![CI](https://github.com/rickyraz/zbeam/actions/workflows/ci.yml/badge.svg)](https://github.com/rickyraz/zbeam/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

zbeam runs Zig workers in a separate process. Elixir can discover them, send
supported requests, and monitor them over a subset of Erlang Distribution. The
native runtime uses explicit ownership rather than a tracing garbage collector.

**Development only.** zbeam is not a complete Erlang node or a production
service. Its CLI binds to IPv4 loopback, has no TLS, and exposes the cookie in
process arguments. Use it only with trusted local peers and a development cookie.

## Try a Zig handler from Elixir

This example needs Linux, Zig 0.17.0, Erlang/OTP with EPMD, Elixir, and Python 3. From the repository root:

```sh
zig build example-custom-worker -Doptimize=safe
sh scripts/interop/ensure_epmd.sh
elixir --erl '+S 2:2' --name custom_client@127.0.0.1 \
  --cookie development_cookie examples/custom_client.exs ./zig-out/bin/zbeam-custom-worker
```

The client starts a guarded native process, calls both workers, and prints:

```text
PASS compiled Zig uppercase handler on both workers
```

The handler in [`examples/custom_worker.zig`](examples/custom_worker.zig)
converts ASCII input to uppercase. Change the function and rebuild the executable
to try another handler. The [Elixir client](examples/custom_client.exs) starts the
supervised `TwoWorkerOwner` with `profile: :custom` and uses `TwoWorkerOwner.call/3`.

A handler borrows the runtime's copied input for the duration of the call and
writes up to 32 bytes to the supplied output buffer. It must not retain either
buffer and must be safe to call concurrently. The runtime accepts input up to
1 MiB, but this uppercase example returns `handler_failed` for input over 32 bytes
and retires that actor. See the [handler contract and wire profile](docs/two-worker-wire.md#compiled-handler-composition-experimental).

## What works

- `serve-worker` provides one PID-addressable SHA-256 worker. The
  [Elixir owner](docs/worker-recovery.md) monitors it and supervises external recovery.
- `serve-workers` provides two fixed SHA-256 workers. Its
  [Elixir owner](docs/two-worker-wire.md#supervised-elixir-owner) admits one request
  per actor, returns `busy` under pressure, and can stop one actor without stopping its sibling.
- A separately compiled handler can run on the two-worker `call` profile under
  the same owner, as in the example above. The ordinary `serve-workers` command
  remains SHA-256.
- The wire subset, handshake, monitoring, and worker profiles are tested with OTP
  25, 26, and 27. The [implementation status](docs/implementation-status.md)
  lists the contracts and evidence.

A sent request may have an unknown outcome after a timeout or disconnect. The
supervised owner does not automatically replay uncertain work; that is not an
exactly-once guarantee. Shutdown is cooperative: if a handler never returns,
the native process must be killed and reaped externally. A panic or memory
corruption can affect both native workers.

The service handles one authenticated peer at a time. Full ETF coverage, RPC,
process links, distributed registry semantics, and a general actor scheduler are
not implemented. The [MVP guide](docs/mvp.md) describes the wire limits and
includes the echo example.

Ports also run outside the BEAM. zbeam explores PID-addressable native workers
with explicit ownership, not process isolation alone. The
[current benchmarks](benchmarks/README.md) include negative results and do not
establish a performance advantage over Ports.

## Build and test

The core build requires Zig 0.17.0 and Git:

```sh
zig build
zig build test-all
zig build test-all -Doptimize=safe
```

Additional checks:

```sh
zig build example-task-runtime                 # two local tasks; no network
zig build test-task-lifecycle -Doptimize=safe  # Linux and Python 3 watchdog
zig build test-worker-recovery -Doptimize=safe # Linux, Python 3, Elixir, and EPMD
zig build test-interop-docker                  # pinned OTP 25/26/27 images; Linux and Docker
```

For native OTP installations, set `OTP_ERL_25`, `OTP_ERL_26`, and `OTP_ERL_27`,
then run `ZBEAM_REQUIRE_ALL_OTP=1 zig build test-interop`. Missing or incorrectly
labeled targets are not passes. Zig 0.17 optimizer names are `debug`, `safe`,
`fast`, and `small`; older evidence retains its original names.

## Battery-pack architecture

| Import | Responsibility | Allowed zbeam dependencies |
|---|---|---|
| `zbeam-etf` | Owned terms and ETF codec | None |
| `zbeam-protocol` | Pure wire and handshake semantics | `zbeam-etf` |
| `zbeam-transport` | EPMD, handshake and framed I/O | Protocol, ETF |
| `zbeam-actor` | Bounded mailbox and demand primitives | None |
| `zbeam-runtime` | Service composition, caller-owned registry and fixed local task owner | All narrower batteries |
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
- [Development sequence and final release gates](docs/development-plan.md)
- [snmalloc research and evaluation plan](docs/snmalloc-evaluation.md), not an integrated backend
- [Protocol primary sources](docs/protocol-sources.md)
- [Architecture decisions](docs/adr/README.md)
- [Verification evidence](docs/evidence/README.md)
- [Port and SHA-256 worker comparisons](benchmarks/README.md)
- [v0.5.0 draft](specs/zbeam-v0.5.0.md), a design target with unimplemented pseudocode

Contribution requirements are in [CONTRIBUTING.md](CONTRIBUTING.md). Security limits are in [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)
