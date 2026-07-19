# Protocol Fixtures

Fixtures preserve byte-level inputs and expected outputs for ETF and Erlang distribution conformance.

Current layout:

- `etf/` — OTP-generated encoded terms with source expressions and expected forms;
- `protocol/` — reviewable structural handshake and framing vectors.

Future captured distribution samples must record provenance, OTP version, generation command, expected result, and license/redistribution clarity. Cookies, host identities, and unrelated traffic must be removed before commit.
