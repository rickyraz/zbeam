# Publication-readiness verification

## Scope

Repository metadata, documentation truthfulness, package surface cleanup, and CI wiring.

## Evidence

- The README explicitly distinguishes the v0.5 design target from implemented code.
- Template arithmetic APIs and placeholder success claims were removed.
- Test names state that they verify suite wiring only.
- `docs/implementation-status.md` lists every major subsystem as unimplemented.
- Primary documentation uses declarative, contributor-facing language; conversational Q&A and assistant-style wording were removed.

## Verification

Environment: Zig 0.16.0 on Linux.

Commands:

```sh
zig fmt --check build.zig src tests examples
zig build
zig build test-all
```

Result: all commands passed on Zig 0.16.0.
