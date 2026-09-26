# OTP interoperability runners

## Native installations

```sh
zig build
OTP_ERL_25=/opt/otp25/bin/erl \
OTP_ERL_26=/opt/otp26/bin/erl \
OTP_ERL_27=/opt/otp27/bin/erl \
ZBEAM_REQUIRE_ALL_OTP=1 ./scripts/interop/otp_matrix.sh
```

`OTP_VERSIONS` selects target majors (default `25 26 27`). Each configured executable must report the matching major; a mislabeled OTP 28 executable cannot pass as OTP 25. Strict mode fails if any selected target is missing. CI selects one required target per matrix job.

Without strict mode, missing targets are reported as `SKIP`, not `PASS`. If no target executable is configured, local `erl` is used only as explicitly labeled development evidence. No Erlang executable is a failure, not a successful empty suite.

## Pinned Docker matrix

```sh
zig build test-interop-docker
```

This runner requires Linux, Docker and a host `epmd` on PATH. It uses pinned Erlang image digests and host networking, then invokes the same strict three-version matrix. It does not mount the repository or share the host PID namespace. Each container is removed after its Erlang command exits.

`ZBEAM_BIN` overrides the native executable under test. GNU `timeout` bounds external commands. Service and OTP children use per-run names and private temporary log directories; failed runs print diagnostic logs before cleanup.

The smoke contract is described in [tests/interop/README.md](../../tests/interop/README.md). It covers the [restricted MVP](../../docs/mvp.md), not arbitrary distribution operations.
