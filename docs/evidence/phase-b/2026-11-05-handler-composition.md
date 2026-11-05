# Compiled handler: synthetic service composition

**Scope:** candidate based on wire-primitives candidate `11b6e32`; Linux WSL2 x86-64, Zig 0.17.0. No custom CLI or live OTP custom-call test is included in this unit.

For `node.Config.service = .workers`, a non-null `custom_handler` creates the private task runtime with that compiled function and selects the `call` parser. The ordinary null configuration retains SHA-256 and `hash`. A handler on another service is rejected. Custom results encode only `output_len` bytes from the runtime-owned inline buffer; an impossible internal length above 32 fails closed and releases its output credit. `InvalidOutputLength` is classified as a fatal two-worker invariant error, not a peer retry.

Synthetic session tests cover rejection of `hash` in custom mode, empty/3/32-byte results across both actors, real handler error and surviving sibling, and invalid length/credit cleanup. Existing tests retain stop, monitor, disconnected-epoch, writer-failure and normal SHA-256 coverage. A service-owner test confirms the configured callback is used, and the node test rejects incompatible configurations. These do not substitute for an authenticated live OTP custom client.

```sh
zig fmt --check build.zig src tests examples
zig build test-all test-labs test-task-lifecycle test-worker-recovery -Doptimize=debug -j2 --summary all
zig build test-all test-labs test-task-lifecycle test-worker-recovery -Doptimize=safe -j2 --summary all
zig build test-interop-docker -Doptimize=safe -j2 --summary all
```

Both full modes passed **73/73 steps, 138/142 newly executed Zig checks with four conditional spin skips**; other steps were cached. Both spin subprocesses were independently killed/reaped, and the SHA-256 owner suite passed 15/15. The pinned OTP 25/26/27 Docker safe regression passed **7/7 steps, three targets and none missing**, with the native compile cached; it tests the existing SHA-256 profiles. Logs are `~/.local/state/zbeam-maintenance/2026-10-29-m2d/handler-compose-full-{debug,safe}.log` and `handler-compose-otp-safe.log`. Actual merged-master CI and end-to-end custom interoperability are separate gates.

**Rollback:** revert this composition, its tests and documentation together; local handlers and the existing SHA-256 profiles remain separate.
