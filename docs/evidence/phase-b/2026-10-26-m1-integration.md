# Bounded M1 accepted into master — 2026-10-26

**M1 W0–W5 is accepted and integrated.** The next milestone is M2 task ownership
and bounded multi-actor lifetimes, not yet started. Package version remains
**0.0.1 pre-alpha**: acceptance is not a production release or full v0.5 conformance.

## Authorization and integration

The owner explicitly approved `size:exception` for PR #3 and normal merge;
[approval record](https://github.com/rickyraz/zbeam/pull/3#issuecomment-6419841418).
The preserved-history diff contained 396 files and 25,859 changed text lines,
including 20,020 historical raw-sample lines. The [review slices](../../m1-review.md)
remain available; tests, data and provenance were not removed to meet the budget.

| Boundary | Result |
|---|---|
| PR #3 candidate | `fc5d72d1a3bc1b4f44397f251cb6cf94049bcd4b` |
| Normal PR #3 merge | `2241e7f4a93b5a5e0ff533169494312ade71b34e` |
| Focused cleanup repair | PR #4, `7e69242d5e723cd09430332a4c420ee503ced064`; 106 changed text lines |
| Normal PR #4 merge / accepted runtime | `88db721ac201f7b61693f08be44d7c245d8c1b73` |

Both actual merge trees equal their checked candidate trees. No history rewrite,
forced branch operation, branch-protection change or research promotion occurred.
Eleven branch names and ten worktrees are retained; the M1 checkout is not deleted.
All nine research topics remain independent. Follow-up status synchronization is
documentation/evidence only and does not change the accepted runtime.

## Current checks and retained failures

| Check | Result |
|---|---|
| PR #3 candidate [40343023213](https://github.com/rickyraz/zbeam/actions/runs/40343023213) | 9/9 jobs |
| PR #3 synthetic merge [40343374154](https://github.com/rickyraz/zbeam/actions/runs/40343374154) | 9/9 jobs |
| Initial actual master [40348895214](https://github.com/rickyraz/zbeam/actions/runs/40348895214) | 8/9; private-EPMD Port cleanup failed, acceptance reopened |
| Repair candidate [40352844901](https://github.com/rickyraz/zbeam/actions/runs/40352844901) | 9/9 jobs |
| Repair synthetic merge [40352855879](https://github.com/rickyraz/zbeam/actions/runs/40352855879) | 9/9 jobs |
| Actual repaired master [40354417903](https://github.com/rickyraz/zbeam/actions/runs/40354417903) | **9/9 jobs**; all six OTP/mode lanes and both owner modes |

The [cleanup diagnosis and regression](2026-10-26-m1-port-cleanup.md) retain the
failed master run and controlled check/use counterexample. Owner/test cleanup
now handles only proven closed-Port errors. All original thirteen scenarios
remain, plus one regression: **14 cases per mode**, split into thirteen ordinary
cases and a complementary private-EPMD case in a fresh VM. Selected actual-master
job logs prove that checkout and both complementary case groups executed.

The earlier [EPMD startup triage](2026-10-26-m1-acceptance.md) and
[OTP 25 installer failure](2026-10-26-m1-ci-runner.md) remain distinct. No failed
workflow was blindly rerun. Preventing the proven startup-race class does not
reconstruct the old runner's exact scheduling trace. Repair whole-run log ZIP
fetches failed transport; individual core/owner job logs and all-nine-job metadata
were fetched instead, without rerunning tests.

## Local and scope evidence

Linux x86-64 WSL2, Zig 0.17.0, `.zig-cache/0.17`; native OTP 25/26/27 use pinned
Docker images. The optional owner separately uses Elixir 1.20.4 / OTP 29.
Actual initial master passed build 5/5, core/labs 63/63 with 91/91 executed tests
per mode, and native OTP 7/7 per mode with zero missing targets. Repaired-master
reruns passed 63/63 core/labs (69 unchanged cached cases; 22 lab executions) and
4/4 recovery steps per mode. The repair also passed twenty complete local
campaigns, ten per mode: **280 ExUnit executions**, not performance/soak evidence.

The accepted profile has one synchronous worker/active peer, owned copies,
positive-demand reads, correlated PID discovery/hash/stop, a 64-slot PID/named
monitor table and externally supervised recovery without replay. Runtime spawn
still registers caller-owned storage; no task scheduler, tracing GC, links,
native supervision tree, alternate allocator or zero-copy path is introduced.
Non-Linux/native-host certification, long soak, OS-OOM/corruption coverage and
production secret/TLS handling remain open.

Raw CI metadata, selected core/owner job logs, normal-merge responses and local
repaired-master results are in `2026-10-26-m1-integration/`. Earlier raw failures
remain in their original linked directories; accepted ADR bodies are unchanged.
