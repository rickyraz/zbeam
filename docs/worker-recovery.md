# Linux worker ownership and recovery example

## Process ownership boundary

`examples/worker_guard.py` launches exactly one non-forking native child. Its
stdin belongs exclusively to the controlling BEAM Port; EOF, including owner or
VM death, kills and waits for that child. The child receives `/dev/null` as stdin,
so it cannot keep the liveness pipe open. Linux `PR_SET_PDEATHSIG(SIGKILL)` and a
post-install parent check also terminate the child if the launcher itself dies.
No shell command interpolation or process-name scanning is used.

The launcher requires Linux and Python 3; it is an optional Elixir deployment
example, not a dependency of any zbeam battery or the native executable. It is
single-threaded before `fork`/`exec`. This contract does not manage arbitrary
forking grandchildren or replace a service manager/cgroup. After abrupt launcher
death, orphan reaping belongs to the Linux init/service manager; verification
checks that no owned process remains live, not that all `/proc` entries vanish
immediately on every host.

Run the independent boundary checks:

```sh
python3 tests/integration/worker_guard_test.py
```

The checks cover stdin EOF, launcher TERM/KILL and native-child exit with bounded
waits and test-owned PID cleanup.

## Runnable monitored worker

Build with the verified Zig 0.16.0 compiler, then run on Linux with Python 3,
Elixir and EPMD installed:

```sh
zig build -Doptimize=ReleaseSafe
epmd -daemon
elixir --name worker_client@127.0.0.1 --cookie local_development_cookie \
  examples/monitored_worker.exs "$PWD/zig-out/bin/zbeam"
zig build test-worker-recovery -Doptimize=ReleaseSafe
```

`NativeWorkerOwner` discovers and monitors the native worker PID, while also
observing its node and owned Port. Startup has a three-second GenServer start
limit and a two-second connection/discovery budget. No work is accepted before
readiness. The example supervisor uses one-for-one restart, a 100-ms owner delay,
and at most three restarts within five seconds.

Call `NativeWorkerOwner.hash(Name, Binary)` rather than raw `GenServer.call`.
A fixed one-record ETS admission slot rejects concurrent callers with `busy`
before their payload reaches the owner mailbox. The owner alone releases it;
caller death between admission/delivery or during work retires the owner rather
than reopening a possibly uncertain operation. `invalid_input` and `not_ready`
are local rejection outcomes. Admitted uncertain work fails with `worker_lost`
or `timeout`; it is never automatically replayed. Fresh work uses a fresh worker
PID and request reference. Old references do not complete replacement requests.

The example sends three exact SHA-256 jobs and shuts down. Fresh short names
avoid old-registration startup races; copying that launcher into an indefinite
service requires a bounded configured name pool or stable-name cleanup barrier.
Otherwise repeated dynamic node atoms can accumulate in the BEAM VM. The native
worker and connection monitor table themselves do not grow with restart count.
The owner assumes exclusive use of its peer connection and disconnects it on
retirement. It does not provide a native supervision tree or a job queue.

## Verification and deployment boundary

The opt-in recovery target runs guard checks, ordinary ExUnit scenarios, the
runnable example, and a separate VM using a private test-owned EPMD port. Faults
are startup-only in `tests/interop/fault_worker.zig`, compiled only for that
target: panic, deterministic allocator failure, noncooperative spin, and a
cancellable pause for the EPMD-loss test. No production fault command is added.
A noncooperative handler can delay EPMD fail-stop too; the external deadline and
process owner remain required. An injected allocation error is not an OS OOM-kill
test, and a panic is not memory-corruption isolation.

The recorded owner example runs on Elixir 1.20.4 / OTP 29; native distribution
behavior separately passes pinned OTP 25/26/27. This does not claim that this
Elixir build runs on those older VMs. Full records and exact commands are in
[M1 verification](evidence/phase-c/2026-10-25-m1.md).

Cookies appear in process arguments in this local example; distribution is not
TLS. Secret delivery, cgroup/service-manager containment, supported Elixir/OTP
pairings and non-Linux deployment need a separate production review.
