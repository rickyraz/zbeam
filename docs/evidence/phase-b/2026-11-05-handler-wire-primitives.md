# Compiled handler: wire primitives and independent vectors

**Scope:** internal primitives based on local handler candidate `354a58c`; Linux WSL2 x86-64, Zig 0.17.0. No custom executable or network profile is enabled by this unit. ADR 0005's SHA-256 service remains unchanged.

The internal parser selects either `hash` or `call` explicitly; the other command and nonbinary arguments return `bad_request`. Both modes retain the same authenticated envelope and 1 MiB input limits. The bounded encoder accepts 0–32 borrowed bytes, copies the encoded frame into its caller-owned 16 KiB scratch before returning, and rejects length 33. No borrowed output survives the synchronous encoding call. Focused tests cover both mode directions, invalid argument type, input sizes 0/1 MiB/1 MiB + 1, and output sizes 0/1/32/33.

`scripts/interop/m3_fixtures.escript` independently generated four exact request/reply frames using pinned OTP 25, 26 and 27 containers with no network. All three outputs were byte-identical, SHA-256 `ce7ea0d4bfc03fa0e0b061b5ae7be6db590c6e2cd0ac79eba6e4f02af5234efa`. `fixtures/protocol/m3.tsv` preserves them; conformance tests compare encoded bytes and decode each payload. Existing M2b fixtures remain unchanged. These are frame vectors, not live custom-service interoperability evidence.

```sh
zig fmt --check build.zig src tests examples
zig build test-all test-labs test-task-lifecycle test-worker-recovery -Doptimize=debug -j2 --summary all
zig build test-all test-labs test-task-lifecycle test-worker-recovery -Doptimize=safe -j2 --summary all
```

Both modes passed **73/73 steps, 133/137 newly executed Zig checks with four conditional skips**, with other steps cached. Both spin probes were independently killed/reaped; the owner suite passed 15/15 in each mode. Logs and independently generated fixture copies are in `~/.local/state/zbeam-maintenance/2026-10-29-m2d/handler-wire-final-{debug,safe}.log` and `m3-vectors-otp{25,26,27}.tsv`.

**Rollback:** revert these internal parser/encoder changes, tests, vectors and evidence together. Activation and end-to-end tests require a separate unit; actual merged-master CI remains a gate.
