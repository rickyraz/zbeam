# Security Policy

## Supported versions

No version is currently supported for production use. zbeam is a pre-alpha research scaffold and does not yet implement authentication or the Erlang Distribution Protocol.

## Reporting

Please report suspected vulnerabilities privately through GitHub's **Security advisories** page for this repository. Do not include cookies, credentials, private packet captures, or exploit details in a public issue.

## Current safety guidance

- Do not expose zbeam to untrusted networks.
- Do not use real Erlang cookies with this scaffold.
- Do not rely on the draft specification as evidence of implemented validation, isolation, or protocol security.
- A future distribution implementation must treat ETF, handshake, fragment, and atom inputs as hostile and enforce explicit bounds before allocation.
