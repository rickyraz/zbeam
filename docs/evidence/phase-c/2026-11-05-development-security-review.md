# Development-profile security review

**Scope:** focused source inspection on 5 November 2026 UTC of the CLI, guardian/owner launcher, cookie handshake, two-worker route, admission table and handler interface. This is not an independent audit, penetration test or production certification. The CLI binds IPv4 loopback; the library does not enforce that restriction for every caller.

| Finding | Evidence and consequence | Development boundary / future gate |
|---|---|---|
| No TLS or authenticated encryption | `src/main.zig` uses a plain loopback TCP stream; the OTP-compatible handshake proves knowledge of a shared cookie using the legacy MD5 challenge, not encrypted messages. Loopback is not an authorization boundary against other local processes or shared network namespaces. | Do not expose this profile to untrusted peers or networks. Remote support requires a separately designed OTP-compatible TLS profile, verified peer certificates/identity, no silent downgrade, negative tests and OTP 25/26/27 interop. |
| Cookie in process arguments | `examples/two_worker_launch.ex` places the BEAM cookie in guardian argv; `examples/worker_guard.py` forwards it to the native argv. Direct CLI and some example OTP commands also take cookies as arguments. Visibility depends on OS permissions and configuration. | Use public, disposable development cookies only. A production gate requires bounded non-argv secret delivery end-to-end, restricted access, cleanup and tests; environment variables alone do not establish secrecy. |
| Trust is node-wide, not per-process authorization | The acceptor validates the shared cookie but does not enforce an allowlist of node names. `wire_route.zig` checks PID/reference node and creation, but a distribution SEND does not identify the originating BEAM process. The owner admission ETS table is public within the BEAM VM. | Treat all code in the connected BEAM node and same-privilege local environment as trusted. Per-client authorization and hostile local-process isolation are not provided. |
| Bounded allocations do not prevent denial of service | A shared stream can block ticks/control behind read admission; only one peer is served at a time. An arbitrary CPU-bound or noncooperative handler can stall cooperative shutdown. | Use external watchdog/kill and trusted workloads. Do not infer availability, fairness or a total RSS bound from admission limits. |
| Compiled handlers execute native code | Borrowing, output bounds and concurrency obligations are not enforced against malicious or memory-unsafe Zig. Both actors share the same native process. | Compile only trusted handlers. External process loss isolation does not sandbox filesystem, network, memory corruption or privileged operations. |

## Local cookie observation

A public sentinel cookie was used in a fresh WSL2 / Elixir 1.20.4 / OTP 29.1.1 run. A probe started the ordinary guarded `serve-workers` child, read only its two owned `/proc/PID/cmdline` files, asserted that each contained the sentinel and printed only the boolean result. It observed the sentinel in **both guardian and native argv**, then closed the guard and observed both child processes exit. The original probe and output are retained at `~/.local/state/zbeam-maintenance/2026-10-29-m2d/cookie-exposure-probe.{exs,log}`; they contain no private credential. This demonstrates exposure in that environment, not the effective access policy of every Linux deployment.

Reproduce the historical observation using only the public sentinel; the checked-in probe rejects other cookies and will fail once both argv exposures are fixed:

```sh
zig build -Doptimize=safe
sh scripts/interop/ensure_epmd.sh
elixir --erl '+S 2:2' --name cookie_probe@127.0.0.1 --cookie zbeam_public_probe_cookie \
  docs/evidence/phase-c/2026-11-05-development-security/cookie_exposure_probe.exs ./zig-out/bin/zbeam
```

Existing safeguards include bounded wire decoding and waits, mutual cookie-proof verification, fail-closed EPMD loss, and tests for no automatic replay. They do not resolve the findings above. Independent security review, adversarial handshake and resource testing, OS containment, non-argv secrets and TLS remain required before a broader trust or deployment claim.
