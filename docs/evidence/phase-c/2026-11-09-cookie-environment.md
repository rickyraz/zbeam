# Cookie delivery through ZBEAM_COOKIE

- **Date:** 2026-11-09 UTC.
- **Base:** master `9ee80562a19812c9192f8f30c5c18c1e7ace51cd`.
- **Follows:** the [development security review](2026-11-05-development-security-review.md), which observed the cookie in both guardian and native argv.

## Change

Every CLI command accepts `-` as its cookie argument and then reads the cookie
from the `ZBEAM_COOKIE` environment variable; an unset or empty variable fails
with `MissingCookie` or `EmptyCookie` before any socket is opened. Positional
cookies keep working. `TwoWorkerLaunch` (used by `TwoWorkerOwner`),
`examples/monitored_worker.exs` and `examples/sha256_worker.exs` pass `-` and
supply the cookie through the Port `env` option; the guardian forwards its
environment to the native child unchanged.

## Exposure after the change

On Linux, `/proc/PID/cmdline` is world-readable, while `/proc/PID/environ` is
owner-only and also readable by root. The cookie therefore stays hidden from
other local users but remains readable by the same OS user. The BEAM nodes in
the examples and tests still receive `--cookie` in their own arguments; using
`~/.erlang.cookie` for them is a separate choice outside zbeam.

## Tests

- `main.zig`: `-` reads `ZBEAM_COOKIE`; missing and empty values are rejected;
  a positional cookie is returned unchanged.
- `scripts/test/cli_smoke.sh`: the usage text names `ZBEAM_COOKIE`; `-` without
  the variable fails with `MissingCookie` and with an empty value fails with
  `EmptyCookie`.
- `two_worker_launch_test.exs`: for the live guardian and native child, argv does
  not contain the cookie and ends with `-`, each `environ` file has no group or
  other permission bits, and the native environment contains
  `ZBEAM_COOKIE=<cookie>`.
- Existing owner, process, custom and M1 example suites run unchanged through
  the new launch path.
- Counter-check: the historical
  [exposure probe](2026-11-05-development-security/cookie_exposure_probe.exs),
  run with its public sentinel cookie, now fails at its first assertion
  (`true = present.(guard)`), because the guardian argv no longer contains the
  cookie. The probe is kept unchanged as a record of the earlier behavior.

## Local results

Linux WSL2 x86-64, Zig 0.17.0, Elixir 1.20.4 / OTP 29.1.1.

- `zig fmt --check build.zig src tests examples` passed.
- `zig build test-all test-labs test-task-lifecycle test-worker-recovery
  -Doptimize={debug,safe} -j2 --summary all` passed 77/77 steps in each mode
  (debug 144/148 and safe 59/61 newly executed tests; only watchdog-gated cases
  skipped; other steps cached), including the launch suite 5/5 and the M1
  monitored example.
- `examples/sha256_worker.exs` verified an exact digest with the environment cookie.
- Logs: `~/.local/state/zbeam-maintenance/2026-11-09-m3/cookie-*.log`.

## Limits

This is not secret management: same-user processes, root, core dumps and any
child that inherits the environment can still read the cookie. TLS, peer
allowlists and an independent security review remain open.

**Rollback:** revert the CLI option, launcher changes, tests and documentation
together; positional cookies are unaffected either way.
