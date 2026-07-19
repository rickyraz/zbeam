# Repository Scripts

**Status:** Script directories are reserved; no helper currently replaces the documented Zig build commands.

## Boundaries

- `test/` — reproducible integration, OTP matrix, fault-injection, and stress runners.
- `bench/` — benchmark orchestration and raw-result capture.
- `lab/` — one-off research experiment runners that remain outside release verification.

Scripts MUST fail on command errors, print tool versions, avoid host-specific absolute paths, and accept secrets through the environment rather than source files. Core checks remain directly runnable through `zig build`.
