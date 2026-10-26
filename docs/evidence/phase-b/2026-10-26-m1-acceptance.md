# M1 merge-result verification — 2026-10-26

**Status:** local acceptance gates passed; PR/CI and review approval remain gates.
This record covers the bounded M1 development profile, not production readiness.
The first new push passed seven jobs but failed both OTP 25 installer lanes before
tests; [runner triage and correction](2026-10-26-m1-ci-runner.md) retain that failure
and pin interop to Ubuntu 24.04. A current all-lane pass remains mandatory.
Master `3919341` was integrated by ordinary merge `664fc81`. The merge tree was
byte-identical to its M1 parent: compiler/documentation changes had already been
backported. Nine research topics remain separate; no scheduler/allocator feature
was imported.

## Registration failure triage and regression

[CI run 40279020842](https://github.com/rickyraz/zbeam/actions/runs/40279020842),
`otp-interop (27, safe)`, failed the first echo registration with
`ConnectionRefused`, then exhausted the unchanged ten-second registration poll.
The old launcher treated successful `epmd -daemon` exit as readiness.

[OTP 27.3 epmd.c](https://github.com/erlang/otp/blob/OTP-27.3/erts/epmd/src/epmd.c),
`run_daemon`, exits the parent after fork, before the daemon child calls `run`.
Daemonization is therefore not a listening/serving barrier. A controlled test of
the old launcher reproduces premature success; a private, reserved non-listening
port produces `ConnectionRefusedError`. The replacement remains blocked until a
real private EPMD answers `-names`. It never kills the shared developer EPMD.

The shared launcher now gives daemon startup and the complete names probe a
five-second budget plus one-second forced-cleanup grace. Tests cover delayed and
already-ready service, start failure, repeated refusal, a hung probe and a
TERM-resistant probe. Error statuses remain observable; neither registration
polling nor native connection error handling was relaxed. All four script
callers and current manual startup recipes use the shared readiness check.

The TERM-resistant regression first exposed that an exiting supervisor shell can
prevent timeout's later KILL from reaching a remaining probe. Keeping that shell
alive until group KILL bounds failed probes, including interrupted sleeps; the
two failed test-development attempts are retained rather than counted as passes.

The original runner's exact scheduling/network trace was unavailable. This is a
source-supported, reproduced startup-race class and its tested prevention, not
proof excluding every other historical trigger. Native EPMD loss remains
fail-stop; no hidden runtime retry/re-registration or demand bypass was added.

## Local verification

Linux x86-64 WSL2; Zig 0.17.0, `.zig-cache/0.17`; native OTP 25/26/27 use the
existing pinned Docker images. Owner examples separately use Elixir 1.20.4 / OTP
29. No global compiler change or production/platform certification is implied.

| Gate | Result |
|---|---|
| Empty-tree master merge, core/labs debug and safe | 63/63 steps, 91/91 executed tests per mode |
| Updated launcher, core/labs debug and safe | 63/63 steps; unchanged logic reused cache, 22 lab cases executed per summary |
| Startup regression | Five unittest cases, including private real EPMD; old launcher counterexample fails as intended |
| Native OTP 25/26/27, debug and safe | 7/7 steps each; all three targets, no missing target |
| External owner, debug and safe | 4/4 steps each; 12 ordinary cases plus one complementary private-EPMD case in a fresh VM per mode |
| Guardian, example and arguments | Standalone guardian, exact three-job example and run/benchmark argument smoke pass |
| Hygiene | Zig formatting, shell parsing and whitespace checks pass |

Raw logs, including the original CI failure and intended counterexample failure,
are retained in `2026-10-26-m1-acceptance/`. New push/PR checks must verify the
actual candidate SHA. A green result does not waive the review-size decision or
claim general OTP compatibility, process links, native supervision, task-owning
spawn, tracing GC, replay, zero-copy or long-soak production safety.
