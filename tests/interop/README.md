# OTP Interoperability Tests

The restricted MVP suite passed on actual OTP 25, 26 and 27 on 2026-09-26. These are repository verification assets, not a consumable package or a full Erlang conformance suite.

The runner is `scripts/interop/otp_echo_smoke.sh`. It verifies:

- accepting and initiating handshakes, including real EPMD discovery;
- exact replies for supported integers, atoms, tuples, lists, PIDs and binaries;
- repeated messages, ignored registered names and an idle interval with OTP ticks;
- bad-cookie rejection without terminating the listener;
- disconnect/reconnect and recovery after an unsupported payload;
- child process loss, bounded `nodedown`, unchanged OTP OS PID and an unrelated responsive local process;
- EPMD registration removal after child exit.

Every external Erlang/probe invocation has a timeout. Cleanup terminates only children created by the test. The cookie is an intentionally public development value, not a deployment credential. The Docker variant requires Linux host networking and a host EPMD executable; it does not require host PID namespace sharing.

Commands and version validation are documented in [scripts/interop/README.md](../../scripts/interop/README.md). Exact image digests and results are in [Phase B evidence](../../docs/evidence/phase-b/2026-09-26-mvp.md).

Process links/monitors, full ETF coverage, actor scheduling and panic/corruption fault injection remain outside this suite. Node monitoring in the isolation check must not be confused with implemented process-monitor control messages.
