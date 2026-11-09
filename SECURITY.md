# Security Policy

## Supported versions

No version is supported for production use. zbeam 0.0.1 is a pre-alpha, restricted Erlang Distribution MVP. It implements mutual cookie challenge/response and bounded input decoding, but it has not had a production security audit.

## Reporting

Suspected vulnerabilities should be reported privately through the repository's GitHub **Security advisories** page. Public reports must not contain credentials, private packet captures or deployment cookies.

## Current boundaries

- The CLI binds IPv4 loopback only. The underlying transport library is not a security sandbox.
- Distribution cookies use the legacy OTP authentication scheme, not encryption. TLS and production secret management are not implemented. The acceptor does not enforce a peer-name allowlist.
- A cookie given as a CLI argument is visible in process listings. With `-` as the argument, the CLI reads `ZBEAM_COOKIE` instead; the bundled Elixir launchers use this, so neither the guardian nor the native argv contains the cookie. On Linux the environment remains readable by the same OS user and root (`/proc/PID/environ` is owner-only), and the example BEAM nodes still receive `--cookie` in their own arguments ([record](docs/evidence/phase-c/2026-11-09-cookie-environment.md)). Test/benchmark cookies are intentionally public and must never be reused in deployment.
- Trust is node-wide, not per BEAM process. The owner admission table is public within its BEAM VM; neither the table nor loopback is an isolation boundary against hostile local code.
- Compiled Zig handlers execute as trusted native code; their borrowing and concurrency obligations are not a sandbox.
- Frames, decoded collections, recursion and aggregate term allocations are bounded. Unsupported matching payloads close their connection rather than being interpreted permissively.
- Handshake, frame-read and write waits have bounded defaults, and the executable stops on EPMD registration loss. There is no concurrent peer service, proactive heartbeat under zero demand, CPU-bound stalled-handler watchdog or automatic re-registration. A non-cooperative handler can still deny service to the next peer.
- Process-loss tests establish observed OTP survival after SIGKILL of the native child, not memory safety or isolation between native actors.
- The v0.5 draft contains unimplemented and explicitly caveated ownership pseudocode. It is not evidence of implemented safety mechanisms.

The service must remain restricted to development with trusted local peers. The [focused source review](docs/evidence/phase-c/2026-11-05-development-security-review.md) records the cookie exposure observation and outstanding TLS, authorization and containment gates; it is not an independent security audit. [MVP limits](docs/mvp.md) and the [risk backlog](docs/research-needed.md) describe the remaining deployment gates.
