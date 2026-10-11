# Unblock::HTTP3 handoff

## Current state

Branch: main
Version: 0.11 prepared, not tagged or published
Last completed work: HTTP1/HTTP2 application API harmonization and release audit

## Implemented in 0.11

- Client->request() accepts named Uniform::HTTP request fields or an
  existing Uniform-compatible Request object.
- Transaction->respond() and send_informational() accept named response
  fields or existing Uniform-compatible Response objects.
- Request and response callback options remain separate from message fields.
- write(), end(), lifecycle methods, streaming body APIs, Datagrams, Capsules,
  Extended CONNECT, 0-RTT and priority remain supported.
- Native ABI, libnghttp3 implementation and Net::QUIC boundary were not changed.
- Client, Server and Integration POD, README, Changes and examples were updated.
- Linux::Event UDP+timer client/server examples use Net::QUIC::Driver and
  separate application handlers from adapter code.

## Release audit

- The 0.11 code was merged into main by fast-forward from
  feature/api-parity-0.11 at commit 6592d5378a18e2c76c4b75e227a267a0b1f5b68f.
- The regular test workflow passed on Perl 5.20, 5.28, 5.36 and 5.44.
- The 5.44 job includes distcheck, disttest, POD syntax and installed
  NativeABI/header checks.
- Real QUIC/TLS/UDP loopback exercises named API forms (t/04).
- Optional Linux::Event live client/server smoke workflow added on main.
  Run 38105724701 passed against released Linux::Event 0.117. It compiled
  both examples and returned HTTP/3 200 / Hello from HTTP/3.
- Package MANIFEST includes examples, tests, API guide and installed
  Integration.pm; MANIFEST.SKIP keeps Handoff.md out of CPAN archives.
- The 0.11 interoperability workflow passed both independent quic-go
  client -> Unblock server and Unblock client -> public HTTP/3 servers.
  GitHub Actions run 38105824175 completed successfully.
- The normal main-branch CI passed on all four supported Perl test versions
  after the interoperability trigger update (run 38105824198).

## Next steps

1. Review the release notes and final change summary with the user.
2. Tag and publish 0.11 to GitHub and CPAN only on explicit user direction.
3. Keep Handoff.md out of CPAN distributions.

## Design boundary

- Modify only Unblock::HTTP3 in this workstream.
- One HTTP/3 Client or Server belongs to one Net::QUIC connection.
- Use Net::QUIC::Driver for QUIC packet output, timers and backpressure.
- Start ordinary HTTP/3 operation after QUIC handshake readiness.
- HTTP/3 owns QUIC stream callbacks after start; do not overwrite them.
- Keep Uniform::HTTP pure Perl; preserve optional native fast paths in engines.
- Handoff.md is repository-only, never part of CPAN distribution.
