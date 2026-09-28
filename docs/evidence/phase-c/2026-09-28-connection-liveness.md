# Connection I/O and EPMD Liveness — 2026-09-28

- Branch `feat/worker-lifecycle`; parent commit `7b812d3` (bounded handshake).
- Zig 0.16.0 on Linux x86-64/WSL2; pinned real OTP 25/26/27 images share host EPMD.
- Runtime default: 90 seconds per distribution-frame read (idle and incomplete frame combined), five seconds per reply write; `null` explicitly disables either. No extra socket read occurs without positive demand.

`transport.deadline.run` joins a losing I/O task before returning. A frame that completes at the timer edge is released even if the timer result wins. Response buffers remain owned until a blocked writer is canceled and joined. External `error.Canceled` propagates unchanged. The timeout wrapper initially exposed a bug: the canceled socket reader saved `error.Canceled`, masking the parent `error.Timeout`; the service stopped instead of accepting the next peer. Error unwrapping now applies only to `ReadFailed`/`WriteFailed`. A partial-frame recovery test reproduces the former hang and passes after this correction.

The executable races the service against a read of its long-lived EPMD registration socket. EOF or unexpected bytes fail-stop the service, joining the active connection/accept task and closing its registration and listening socket. It never silently serves an undiscoverable name. This is a synthetic socket-loss test; the host EPMD daemon was not killed, and no re-registration is implemented.

Tests: a partial distribution header times out and a later authenticated peer succeeds; a peer that never reads a 16 MiB response makes the writer time out and frees its owned response; real TCP pause/resume and cancellation still preserve one outstanding frame. Debug and ReleaseSafe `zig build test-all -j2 --summary all` passed **53/53 tests plus CLI**, 27/27 steps. `zig build test-interop-docker -j2 -Doptimize=ReleaseSafe --summary all` passed OTP **25/26/27** in both roles. Logs: [Debug](2026-09-28-liveness-debug.log), [ReleaseSafe](2026-09-28-liveness-release.log), [OTP](2026-09-28-liveness-otp.log). Expected peer warnings include `Timeout`, `InvalidDigest` and `PacketTooLarge`.

Unresolved: idle versus mid-frame timeout distinction; proactive ticks during zero-demand pauses; non-cooperative CPU handlers; EPMD restart/re-registration; general TCP liveness beyond one peer; separate blocked-handshake-write injection. No assertion of full OTP compatibility or production readiness follows from these tests.
