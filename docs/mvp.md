# Single-Actor MVP

- **Scope:** local development, one synchronous registered echo actor, one active distribution connection.
- **Profile:** bounded ETF subset, OTP 23+ handshake, pass-through distribution framing.
- **Verification date:** 2026-09-26.

This MVP is not the full v0.5 design, a general Erlang node, or a production release. Compatibility means the documented operations passed against actual OTP 25, 26, and 27 runtimes. It does not mean arbitrary Erlang terms, RPC, links, process monitors, or OTP behaviours work.

## Acceptance gates

| Gate | Implementation and executable evidence |
|---|---|
| Independent batteries and deterministic checks | `zig build test-all`; ADR 0001 build graph |
| EPMD registration, lookup and removal | Client integration tests; OTP smoke registration/discovery and removal after child exit |
| Authentication in both directions | OTP matrix accepting echo service and initiating `probe`; bad-cookie rejection |
| Repeatable actor messaging | Multiple exact round trips, ignored unknown names, idle tick traffic |
| Bounded input and memory ownership | Frame cap before allocation; ETF depth, collection and aggregate allocation caps; testing allocator leak checks |
| Demand reaches the socket boundary | Zero-credit read/allocation oracle; unbuffered reads; 64 MiB TCP saturation/resume and cancellation stress |
| Failure and reconnect | Bad cookie, oversized frame, unsupported payload, clean disconnect, subsequent connections |
| External process-loss isolation | SIGKILL of the test child; OTP observes `nodedown`, retains its OS PID and responds through an unrelated local process |
| Reproducible baseline | Port versus distribution latency, throughput, memory snapshots, restart sample and scheduler activity |

Records: [Phase B](evidence/phase-b/2026-09-26-mvp.md), [Phase C](evidence/phase-c/2026-09-26-mvp-runtime.md). These gates establish this restricted MVP, not completion of every roadmap milestone.

## Build and run

Verified toolchain: Zig 0.16.0 on Linux x86-64. Deterministic suites do not require a running EPMD daemon:

```sh
zig build
zig build test-all
zig build test-all -Doptimize=ReleaseSafe
```

Start the development service in one terminal:

```sh
epmd -daemon
./zig-out/bin/zbeam serve zbeam_echo development_cookie
```

Send a request from another terminal:

```sh
erl +S 2:2 -noshell -name client@127.0.0.1 -setcookie development_cookie -eval '
  N = list_to_atom("zbeam_echo@127.0.0.1"),
  true = net_kernel:connect_node(N),
  M = {self(), hello},
  {echo, N} ! M,
  receive M -> io:format("echo passed~n") after 3000 -> halt(1) end,
  halt().'
```

`serve` remains available after the client disconnects. Stop it with the process supervisor or Ctrl-C. OS descriptor closure removes its EPMD registration.

### Executable commands

| Command | Lifetime |
|---|---|
| `zbeam echo NAME COOKIE [COUNT]` | One accepted connection; default one handled message; zero runs until disconnect |
| `zbeam serve NAME COOKIE [COUNT]` | Sequential accepted connections until stopped; COUNT is per-peer, default unlimited |
| `zbeam probe NAME COOKIE PEER` | Register locally, look up PEER, initiate a handshake, verify one request/reply and exit |

Names are short names; the CLI appends `@127.0.0.1`. The service listens only on IPv4 loopback. Counts exclude ticks and ignored destinations. `probe` expects an OTP process registered as `echo` that receives `{From, Value}` and sends `From ! {From, Value}`. Example OTP peer:

```sh
erl +S 2:2 -noshell -name otp_echo@127.0.0.1 -setcookie development_cookie -eval '
  register(echo, spawn(fun Loop() ->
    receive {From, Value} -> From ! {From, Value}, Loop() end
  end)),
  receive stop -> halt() end.'
# In another terminal:
./zig-out/bin/zbeam probe zig_client development_cookie otp_echo
```

Cookies in CLI arguments are visible in process listings. These commands are development interfaces, not secret-management or TLS interfaces.

## Wire contract

- EPMD: ALIVE2 registration and PORT_PLEASE2 lookup, including the two-byte error response. The registration socket remains open for the node lifetime.
- Handshake: version-6, OTP 23+ `N` format, mutual cookie challenge/response, fresh random challenge for each service connection. A deterministic challenge override exists only for tests.
- Distribution: four-byte lengths, zero-length ticks and PASS_THROUGH (`112`). Each control/payload external term has its own ETF version marker.
- Service: `{6, FromPid, CookieAtom, RegisteredName}` (`REG_SEND`); matching `echo` receives a `{2, CookieAtom, FromPid}` (`SEND`) reply containing the same supported value. Unknown registered names are discarded without decoding their payload.
- ETF: signed i32-valued integers (stored in i64), UTF-8 atoms, tuples, binaries, proper lists/byte strings, nil and `NEW_PID_EXT`. Maps, floats, large integers, references, ports, functions, bitstrings, compressed ETF and improper lists are not accepted.
- Optional process-monitor, atom-cache and fragmentation flags are not advertised. Required modern OTP baseline flags are still advertised to establish connections; those flags must not be interpreted as a complete ETF implementation. A matching unsupported payload closes that connection.
- Ordinary `net_kernel:connect_node/1` plus registered send is supported. `net_adm:ping`, `rpc:call`, `gen_server:call`, distributed `global`, process links and process monitors are not implemented. Node-down observation is separate from process monitoring.

Primary field definitions are indexed in [protocol-sources.md](protocol-sources.md). Tests deliberately reject unnegotiated cached/fragmented framing instead of allocating partial-assembly state.

## Limits and ownership

| Bound | Default |
|---|---:|
| Handshake payload | 1,024 bytes |
| Distribution body, excluding four-byte length | 16 MiB |
| ETF binary | 16 MiB |
| ETF collection length | 1,048,576 elements |
| ETF nesting | 64 levels |
| ETF atom | 255 UTF-8 bytes (a deliberately narrower policy than the complete ETF atom limit) |
| Aggregate owned storage for one decoded ETF term | 32 MiB |

`node.Config.limits` propagates to framing and echo decoding. Control and payload have separate ETF allocation budgets; their storage can coexist. The allocation budget counts term arrays and copied bytes, not allocator overhead or temporary encoding buffers. It is not a 32 MiB process RSS guarantee.

The dispatcher owns one input packet at a time. `handle(allocator, packet)` borrows the packet only until it returns and returns either `null` or an owned response. The dispatcher frees both on success, error or cancellation. Escaping a borrowed packet requires an explicit copy. All decoded ETF bytes are owned copies; there is no transport arena, promotion API or zero-copy claim.

## Demand and lifecycle

After authentication, the actor starts with one credit. A read atomically reserves it before touching the reader or allocator. No buffered read-ahead is permitted. Handling and reply flushing finish before the next credit is granted. Ticks and ignored destinations also restore the reserved credit. A slow handler or blocked reply therefore stops subsequent reads; no queue hides this pause.

EPMD and handshake reads are control-plane operations before actor demand applies. The lower-level `readPacket` helper is ungated; actor-facing code uses `readDemandedPacket`, which returns `NoDemand` without reading or allocating and rejects buffered readers. A failed partial read is terminal, so its credit is not refunded into a reusable connection.

Each accepted connection starts with fresh reader and demand state. No packet, queue, atom cache or fragment state survives reconnect. TCP reconnect retains the running node's EPMD creation; OS restart requires a new EPMD registration. No outbound retry/backoff or resumption of interrupted messages is implemented.

The service closes malformed/authentication-failing connections and accepts the next peer. The runtime now applies a five-second total handshake budget in both roles (transport callers can configure or disable it); timed-out peers release resources before the next accept. Cancellation and allocation failure propagate to its caller. EOF at a frame boundary is a clean disconnect; a partial header/body is `Truncated`. There are no detached runtime tasks.

The local `Mailbox(T)` and `Runtime(T)` remain separate reusable primitives. `spawn` registers a mailbox; it does not schedule an actor task. Storage is caller-owned, bounded and must outlive all users. Tokens enforce logical ownership, reject zero IDs and prohibit concurrent receives even with a copied token; they are not unforgeable task capabilities. All operations must be joined before registry/mailbox destruction. Termination closes the queue but does not make already-resolved mailbox pointers safe to free immediately. `Mailbox(T)` copies message values; it does not destroy nested allocations. Senders/consumers must define payload transfer and drain/release queued owned payloads themselves.

## Verification commands

Native installations:

```sh
OTP_ERL_25=/path/to/otp25/bin/erl \
OTP_ERL_26=/path/to/otp26/bin/erl \
OTP_ERL_27=/path/to/otp27/bin/erl \
ZBEAM_REQUIRE_ALL_OTP=1 zig build test-interop
```

Linux with Docker and a host `epmd` executable:

```sh
zig build test-interop-docker
```

The Docker runner pins image digests, uses host networking, and checks all three major versions. The native runner rejects mislabeled executables. A local OTP 28 fallback is explicitly development evidence, not a full matrix pass. CI selects one required target per job with `OTP_VERSIONS`.

```sh
ERL_FLAGS='+S 2:2' zig build bench-port-vs-zbeam -Doptimize=ReleaseSafe -- 1000
```

## Remaining work outside this MVP

1. Distribution read/write deadlines and stalled-handler diagnostics; handshake now has an independently verified total deadline. A peer can currently monopolize the single connection; prolonged pauses also delay ticks and can trigger OTP disconnects.
2. Complete mandatory ETF coverage, control semantics, process links/monitors and broader version/architecture tests before a general compatibility claim.
3. An OTP-sender backpressure oracle. Current socket saturation evidence uses a Zig TCP sender, not a measured BEAM distribution queue.
4. Crash injection for panic, allocator failure and deliberate corruption; SIGKILL evidence alone does not prove those cases or isolation between local actors.
5. Performance across payload sizes, concurrent workloads and external supervision/restart policies; the committed baseline is one small sequential workload.
6. EPMD-loss detection, outbound reconnect policy and production cookie/TLS configuration.
7. Ownership/arena research only after the copied implementation demonstrates a measured bottleneck.

These are tracked in [research-needed.md](research-needed.md); none is silently treated as implemented.
