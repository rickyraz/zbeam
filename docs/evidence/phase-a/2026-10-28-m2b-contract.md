# M2b wire contract decision — 2026-10-28

ADR 0005 records the owner's direction to complete M2b as authorization to
finalize the bounded design. It resolves private runtime ownership, sequential
control output, stop ordering and old-epoch drainage. Acceptance of the design
is not acceptance of a public implementation or of OTP compatibility.

The decision was checked against `wire_admission.zig`, `wire_gate.zig`,
`wire_output.zig`, `wire_monitor.zig`, `wire_encode.zig`, `wire_route.zig`,
`wire_session.zig` and `wire_connection.zig`; earlier unit records describe
actual tests and remaining gaps. This documentation-only unit changes no runtime,
protocol, transport, build or test code. Review links and `git diff --check`;
no new runtime test is claimed. Rollback this ADR/index/status/plan/spec update
as one design unit. ADRs 0001–0004 remain unchanged.

Next: authenticated service/CLI integration, independent vectors and actual OTP
25/26/27 in both modes; process recovery, shutdown and saturation remain required
acceptance evidence, not implied by internal tests.
