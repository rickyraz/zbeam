# M2c owned-process test oracle — 2026-10-29

The launcher and owner fault suites share one test-only helper for bounded
polling, terminal procfs states and identifying the guardian's owned child.
The helper never signals by process name. Permission/malformed procfs errors
remain failures; only missing and terminal states count as not live.

Linux/WSL, Elixir 1.20.4 / OTP 29: the existing actual-launcher suite passed
three tests in 20 fresh VMs after extraction. This refactor changes no production
or wire behavior. Roll back the helper and launcher-test extraction together.
