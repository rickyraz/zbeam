# Production two-worker EPMD loss — 2026-10-28

The actual `serve-workers` executable—not the private-port fixture—was tested
against an EPMD instance owned inside an isolated Docker network and PID
namespace. The test authenticates an OTP peer, discovers and monitors a worker,
terminates its own EPMD, requires node-down plus `noconnection`, waits for the
native process to exit nonzero and checks `EpmdRegistrationLost` in its log.
The shared host EPMD is never targeted.

Zig 0.17.0 Linux/WSL: pinned OTP 25, 26 and 27 images in both debug and safe
passed `zig build test-interop-docker -Doptimize=<mode> -j2 --summary all`, 7/7
steps per mode, three production-EPMD markers and three two-worker OTP markers
per mode, zero missing targets. The script refuses to run unless explicitly
marked for an isolated namespace; the unmarked-host negative check passed. The
flag is a safeguard, not proof by itself of isolation; the runner supplies
`docker run --network none` and the default private PID namespace.

This is a controlled daemon loss on the tested WSL/Docker setup, not a native
host/OS-OOM certification or automatic EPMD re-registration. Remove the isolated
script and its Docker-matrix hook together to roll back; production code is
unchanged. Native CI OTP lanes and the separate guarded recovery fixture remain
independent checks.
