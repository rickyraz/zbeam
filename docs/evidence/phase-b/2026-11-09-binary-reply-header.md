# Header-plus-payload binary replies

- **Date:** 2026-11-09 UTC.
- **Requirement:** [ADR 0007](../../adr/0007-bounded-handler-output.md) step 2. No observable behavior changes in this step.

## Change

`wire_encode.binaryReplyHeader` encodes `{Ref, {ok, <<>>}}` in the existing 16 KiB
scratch, then patches the binary length and the frame length for a `len`-byte
binary of at most `max_binary` (64 KiB). The session writes that header followed
by the borrowed output bytes through the new
`transport.distribution_io.writePacketParts`, which checks that the frame length
covers both parts before writing. The custom `call` reply now uses this path; its
output is still at most 32 bytes because the runtime is unchanged.
`wire_encode.Result` no longer has a `.binary` variant.

## Tests

- For both short and 255-byte node names, the header plus payload equals the
  generic encoder's frame byte-for-byte for 0, 1, 32, 33, 4 096 and 65 536
  bytes; 65 537 returns `OutputTooLarge`.
- Split writes reject a mismatched or truncated length before writing.
- `scripts/interop/m3_fixtures.escript` adds `reply_large`, a 300-byte reply.
  Pinned OTP 25, 26 and 27 containers produced byte-identical output, SHA-256
  `bbd8d7a7a6f7edcd4635c6feed98a34b847f655b581a8b58b9adf69ed1b9226a`; the first
  four vectors are unchanged. The conformance test checks the new vector.

## Local results

Linux WSL2 x86-64, Zig 0.17.0, Elixir 1.20.4 / OTP 29.1.1, Docker.

- `zig fmt --check build.zig src tests examples` passed.
- `zig build test-all test-labs test-task-lifecycle test-worker-recovery
  -Doptimize={debug,safe} -j2 --summary all` passed 77/77 steps in each mode
  (debug: 53/55 newly executed tests; safe: 154/158), with the watchdog-gated
  skips only; other steps were cached.
- `zig build test-interop-docker` (debug) passed all three pinned OTP targets,
  none missing, including the live custom call/reconnect/failure/stop profile.
- Logs: `~/.local/state/zbeam-maintenance/2026-11-09-m3/encoder-*.log` and
  `m3-vectors-otp{25,26,27}.tsv`.

**Rollback:** revert the encoder, transport helper, session call site, vector and
this record together.
