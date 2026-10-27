# Internal two-worker request decoder — M2b prerequisite

`wire_route.zig` decodes the proposed discovery/hash/stop and monitor control
shapes using the existing bounded M1 packet/ETF codec. It does not read a
socket, write a reply or register any endpoint. Decoded actions borrow either
the caller-owned packet/control or a payload owned by `Parsed`; both must remain
alive until the action is consumed, and `Parsed.deinit` frees its payload.

Recognized envelopes require reply PID and reference node/creation to match the
authenticated peer; discovery additionally matches REG_SEND's sender PID. A
stale/unknown PID or unrecognized registered name is dropped before decoding
its payload, as in M1. Unsupported shapes and peer mismatch remain errors;
monitor parsing requires both negotiated flags. Discovery names `a`/`b`, error
semantics and all connection/stop behavior remain proposed in ADR 0005.

Four tests use locally encoded packets to exercise discovery/hash/stop routing,
unknown/stale routes, monitor negotiation, spoofed discovery envelopes, exact
1 MiB/oversize binary and eight deterministic allocation-failure positions with
balanced cleanup. This is **not** independent OTP interoperability or conformance
for the proposed wire profile. Connected service, output ordering, stop/reconnect
lifecycle, packet fixtures and OTP 25/26/27 remain mandatory.

Linux x86-64 WSL2/Zig 0.17.0: debug/safe core/labs/lifecycle each completed
69/69 steps, 104/106 newly executed checks passed, two conditional skips and
unaffected cached runs. Standalone watchdog/example passed. Twenty fresh runtime
launches per mode each reported 53 passed, one conditional skip. Raw logs are
retained adjacent. Rollback removes the decoder/test import and this record;
M1 wire and public exports remain unchanged.
