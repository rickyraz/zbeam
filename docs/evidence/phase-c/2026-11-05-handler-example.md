# Compiled handler: runnable Zig and Elixir example

**Scope:** candidate based on composition candidate `489a15d`; Linux WSL2 x86-64, Zig 0.17.0, Elixir 1.20.4 / OTP 29.1.1. This is a development example, not production or full compatibility acceptance.

`zig build example-custom-worker` builds a separate executable whose Zig handler uppercases ASCII bytes and returns 0–32 bytes. Inputs above 32 bytes cause `handler_failed` and actor retirement in this particular example; the runtime's input bound remains 1 MiB. Only this executable exposes `serve-custom`; the default `zbeam` executable rejects that command. The existing `serve-workers` command remains SHA-256 in both executables. The guarded launcher accepts only the two explicit commands; its existing three-argument form still selects `serve-workers`.

`examples/custom_client.exs` starts the guarded custom executable, discovers two distinct PIDs, checks exact `HELLO` and `WORLD` results through both actors and closes the connection/child. It passed in the debug and safe recovery runs and in **five additional fresh OTP 29 VMs** using the installed debug example. The launcher rejects an unrecognized command. CLI tests verify default-command separation, invalid names and unexpected arguments. A focused Zig test verifies the example function and overlength failure.

```sh
zig fmt --check build.zig src tests examples
zig build test-all test-labs test-task-lifecycle test-worker-recovery -Doptimize=debug -j2 --summary all
zig build test-all test-labs test-task-lifecycle test-worker-recovery -Doptimize=safe -j2 --summary all
```

Both full modes passed **76/76 steps, 40/42 newly executed Zig tests with two conditional skips**; other Zig test steps were cached. The two spin cases were separately killed/reaped; the owner suite passed 15/15. The example is part of `test-worker-recovery`, so supported Elixir/OTP matrix lanes execute it rather than merely compiling it. Local logs are `~/.local/state/zbeam-maintenance/2026-10-29-m2d/handler-example-full-{debug,safe}.log` and `handler-example-repeat-{1..5}.log`.

Custom handler fault, stop/reconnect, broader OTP matrix and actual merged-master CI are separate gates. The example does not implement generic state, dynamic loading, preemption, replay, TLS, physical-memory certification or a custom-call supervised owner.

**Rollback:** revert the example executable/client, launcher option, build/test wiring and documentation together; the default SHA-256 executable and custom runtime composition remain separate.
