# Unblock::HTTP3 handoff

## Current work

Branch: feature/api-parity-0.11
Base: main at aade7344a3e62a0cbc7a3b78e9471681b1c526f4

Goal: align the HTTP/3 application API with the released HTTP1/HTTP2
Client, Server and Transaction APIs without replacing the QUIC transport
integration with a false TCP-style byte-stream abstraction.

## Implemented

- Client->request() accepts named Uniform HTTP fields and per-request
  callbacks/options, or an existing Uniform-compatible Request object.
- Transaction->respond() accepts named response fields or an existing
  Uniform-compatible Response object.
- Transaction->send_informational() accepts named fields or a Response
  object. HTTP/3 still rejects status 101.
- Existing Transaction->write(), end(), lifecycle methods, streaming
  Body::Stream / Body::Reader, HTTP Datagram, Capsule and 0-RTT APIs remain.
- Native ABI, libnghttp3 binding, and Net::QUIC boundary are unchanged.
- Version is prepared as 0.11; Changes, test expectations, and CI dist
  paths have been updated.
- The README, Client and Server POD, and docs/APPLICATION-API.md explain
  the common application API.
- Installed Unblock::HTTP3::Integration POD explains Net::QUIC::Driver,
  UDP, timers and backpressure.
- Complete Linux::Event client/server examples show real integration
  code separated from application callbacks.
- t/22-named-arguments.t tests named fields, callback option separation,
  object identity and argument validation.
- Existing t/04-http3-loopback.t now runs the named forms through real
  UDP, QUIC, TLS and HTTP/3.

## Test and release work

GitHub Actions runs tests on Perl 5.20, 5.28, 5.36, and 5.44,
including distcheck, disttest and installed NativeABI checks on 5.44.
Check that the HEAD branch workflow is green before merging.

The Linux::Event example scripts rely on the separately maintained
Linux::Event distribution and are not executed by the standard HTTP/3
dependency-only CI job. They require a separate runtime smoke test.

Do not merge, tag, publish to CPAN or modify another repository without
explicit user approval.

## Design reminders

- There is one HTTP/3 Client or Server per QUIC connection.
- Net::QUIC::Driver owns packet output and timers. Do not duplicate it.
- A normal HTTP/3 start happens after the QUIC handshake is ready.
- HTTP/3 installs stream callbacks; an adapter must not overwrite them.
- Uniform::HTTP stays pure Perl, with its native fast path in the engine.
- Handoff.md stays repository-only, excluded from the CPAN manifest.
