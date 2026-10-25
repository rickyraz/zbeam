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
waits and test-owned PID cleanup. Elixir ownership and full worker recovery need
the additional integrated verification recorded in the M1 evidence.
