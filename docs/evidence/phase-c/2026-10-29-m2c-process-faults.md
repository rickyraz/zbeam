# M2c process loss, restart intensity and admission — 2026-10-29

The actual guardian/native process is killed separately with two uncertain
requests; both fail and a supervised replacement uses different PIDs. A second,
independently guarded BEAM VM is killed while its two requests are held against
a stopped native child. Its inner guardian and native child and the outer test
guardian all become terminal. Three rapid native kills exceed the configured
restart intensity and leave no live owned child. The test oracle forgets each
confirmed terminal PID; an injected probe verifies it is not checked again.

A separate 80-caller test uses 256-byte inputs with the native process stopped:
78 calls report `busy`, two remain admitted, the table contains two tickets,
and those two complete with the exact digest after resuming. A 1 MiB input is
tested separately against a running child. These are admission observations,
not bounds on arbitrary BEAM messages, all caller-held binaries or total RSS.

The first load fixture used 1 MiB inputs with a stopped peer and failed because
the owner had exited. Its cause was not captured; a non-suspending distribution
send can fail under backpressure, but that is not established as the unique
cause. The smaller fixture tests admission without claiming large-message
availability under saturation. The initial concurrent debug/safe full run also
failed at the M2b private EPMD readiness check when the owned daemon had exited;
its temporary daemon log is unavailable and the cause is unknown. Both failures
are retained. A subsequent isolated debug run and final sequential runs passed.

Linux/WSL Elixir 1.20.4 / OTP 29: five process tests passed in 25 fresh VMs;
the nine-test owner suite passed in 20 fresh VMs. Zig 0.17.0 debug and safe:
73/73 steps, 35/36 newly executed Zig checks with one conditional skip per mode,
remaining steps cached; M1/M2b recovery and the external watchdog passed.
No native-host soak, memory/RSS ceiling, or production availability is implied.
Roll back the fault suite, oracle refinement and test hook together.
