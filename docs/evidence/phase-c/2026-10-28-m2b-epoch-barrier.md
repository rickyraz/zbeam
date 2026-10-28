# Disconnect epoch join barrier — 2026-10-28

A loopback test holds an accepted old-epoch job at a test-only event barrier,
closes the peer and observes the reader/collector group join. The connection has
not returned at that point. Releasing the job permits drain, connection return
and verification that all task reservations/results are free. The earlier
reconnect test separately checks that the next peer gets only its own exact
reference and digest. No elapsed-time sleep is used as proof of ordering.

Zig 0.17.0 Linux/WSL: `zig build test-unit -Doptimize=<debug|safe> -j2
--summary all` passed 15/15 steps and 75/76 newly executed checks with one spin
skip in each mode. Thirty fresh runtime launches per mode passed 72 tests with
one skip each. No runtime code changes; remove this test and evidence to roll
back. Drain is still cooperative and can wait indefinitely for CPU spin; an
external process owner must kill/reap instead of freeing live storage.
