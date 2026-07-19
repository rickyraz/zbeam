# Protocol Fixtures

Fixtures preserve byte-level inputs and expected outputs for ETF and Erlang distribution conformance.

Planned layout:

- `etf/` — encoded terms with source expression and expected decoded form;
- `distribution/` — handshake, control-message, framing, and fragmentation samples.

Every fixture requires provenance, OTP version, generation command, expected result, and license/redistribution clarity. Cookies, host identities, and unrelated captured traffic must be removed before commit.
