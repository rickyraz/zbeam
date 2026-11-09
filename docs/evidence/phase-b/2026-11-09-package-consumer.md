# Fetched-package consumer

- **Date:** 2026-11-09 UTC.
- **Base:** master `b23814922a31d2701cd70df09b58ea9a45a8d6fb`.
- **Requirement:** development plan D5: the library must build from its exported archive, not only from this checkout.

## Check

`zig build test-package` runs `scripts/test/package_consumer.sh` with the same Zig
executable. The script:

1. archives every tracked or untracked-but-not-ignored file that exists in the
   checkout, so uncommitted edits are included;
2. copies `tests/package` to a temporary directory and, with a temporary global
   cache, runs `zig fetch --save=zbeam file://…/zbeam.tar.gz`;
3. requires the fetched package to contain exactly the `build.zig.zon` paths
   (`LICENSE`, `README.md`, `build.zig`, `build.zig.zon`, `src`);
4. builds and runs a consumer that imports `zbeam-etf`, `zbeam-actor` and the
   `zbeam` umbrella: an ETF round trip, a one-slot mailbox that refuses a second
   message, and a SHA-256 digest through `TaskRuntime`.

The zbeam `build.zig` configures without `examples`, `tests`, `fixtures`,
`benchmarks` or `scripts`, because none of them are needed unless their steps run.
The CI `test` job now runs this step.

## Results

Linux WSL2 x86-64, Zig 0.17.0.

- Passed: `PASS package consumer: ETF round trip, bounded mailbox, SHA-256 ba7816bf`.
- Counter-check: with `"src"` removed from `paths`, the script failed at the
  package-content comparison; restoring it passed again.
- Logs: `~/.local/state/zbeam-maintenance/2026-11-09-m3/package-*.log`.

## Limits

This covers one host target and a `file://` URL, not a published release, other
operating systems or a registry. No release tag exists.

**Rollback:** remove the build step, CI line, script, `tests/package` and this record.
