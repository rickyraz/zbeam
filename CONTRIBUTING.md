# Contributing

zbeam is pre-alpha research software. Small, evidence-backed changes are preferred over broad implementations.

## Before opening a change

1. Read `README.md`, `docs/implementation-status.md`, and the touched module.
2. For major design work, also read `specs/zbeam-v0.5.0.md` and `docs/research-needed.md`.
3. Open an issue before changing a protocol contract or public API.

## Rules

- Keep transport ownership out of actor business logic.
- Add tests with every behavior change.
- Do not claim OTP compatibility, zero-copy behavior, safety, or performance without reproducible evidence.
- Treat all network input as untrusted and enforce explicit size limits.
- Keep one pull request focused on one engineering concern.
- Use English for repository code, issues, pull requests, and primary documentation.

## Documentation voice

Repository documentation addresses maintainers, contributors, implementers, and reviewers.

- Use declarative headings and project-centered language.
- Record status, requirements, decisions, risks, and acceptance evidence directly.
- Avoid conversational Q&A framing, second-person guidance, assistant-style offers, and unsupported first-person opinion.
- Distinguish design targets from implemented behavior in every status-bearing document.

## Checks

```sh
zig fmt build.zig src tests examples
zig build
zig build test-unit
zig build test-integration
zig build test-conformance
zig build test-stress
zig build test-all
zig build test-interop  # requires OTP_ERL_25/26/27 for target-matrix passes
```

Protocol changes must include a real OTP fixture or black-box conformance case. Runtime changes must include the smallest stress test that would fail if the invariant regressed.

## Evidence

Record verification in the matching directory:

- `docs/evidence/phase-a/` — logic and contract
- `docs/evidence/phase-b/` — integration and protocol
- `docs/evidence/phase-c/` — runtime, network, and stress

Negative results are useful and should not be hidden.
