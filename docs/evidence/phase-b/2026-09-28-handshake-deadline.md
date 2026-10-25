# Handshake Deadline — 2026-09-28

- Branch: `feat/worker-lifecycle`, based on `11c3319` (restricted MVP).
- Environment: Zig 0.16.0, Linux x86-64/WSL2; pinned real OTP 25/26/27 Docker targets using host EPMD.
- Scope: total timeout for the accepting and initiating handshake only, not a distribution-frame deadline or handler preemption.

`runtime.node.Config.handshake_timeout` defaults to five seconds. The direct `transport.handshake_io.Config.timeout` is optional and defaults to `null` for callers that own a separate deadline. A single `std.Io.Select` races the *whole* handshake against the timer; canceling joins the losing task before its stream, allocator or reader can be released. A late successful `Peer` is explicitly deinitialized. `error.Canceled` and allocation failure are propagated rather than disguised as `error.Timeout`. A timed-out service peer closes at the connection boundary and does not consume the next peer's state.

Deterministic socket tests reproduce partial NAME length, partial REPLY after valid NAME/challenge, and an initiator blocked awaiting status. An external cancellation test verifies that the parent receives `error.Canceled` instead of a spurious timeout. The first two expire; the next authenticated peer succeeds. Previous bad-cookie and coalesced-frame tests remain. `std.Io` timeout/cancellation is not CPU-bound Zig handler preemption.

```sh
zig build test-all -j2 --summary all
zig build test-all -j2 -Doptimize=ReleaseSafe --summary all
zig build test-interop-docker -j2 -Doptimize=ReleaseSafe --summary all
```

Both deterministic builds passed **51/51 Zig tests plus CLI smoke**, 27/27 steps. OTP 25/26/27 passed the existing accepting/initiating and rejection/reconnect/isolation matrix; no new OTP-specific partial handshake sender was added. Logs: [Debug](2026-09-28-handshake-debug.log), [ReleaseSafe](2026-09-28-handshake-release.log), [OTP matrix](2026-09-28-handshake-otp.log). Expected `InvalidDigest`/`PacketTooLarge` peer-rejection warnings are not failed test status.

Unverified: controlled write stalls at each handshake step, very large host scheduling delays, native-host repetition outside WSL2, heartbeat-versus-demand policy, distribution read/write deadlines and active EPMD-loss detection. Those remain separate work, not implied by this gate.
