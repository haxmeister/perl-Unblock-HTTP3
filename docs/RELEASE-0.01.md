# Unblock::HTTP3 0.01

This is the first release of Unblock::HTTP3, a standalone HTTP/3 protocol engine
for Perl.

## Highlights

- real HTTP/3 over Net::QUIC 0.04
- Uniform::HTTP 0.04 as the runtime HTTP message layer
- multiplexed requests and responses
- buffered and streaming bodies
- request and response trailers
- informational responses
- strict HTTP field, routing, and Content-Length validation
- basic CONNECT and generic Extended CONNECT
- RFC 9297 Capsule Protocol
- RFC 9297 HTTP Datagrams
- generic extension SETTINGS and extension unidirectional streams
- RFC 9218 priorities and PRIORITY_UPDATE
- resource limits and bounded buffering
- graceful HTTP/3 shutdown
- persistent HTTP/3 SETTINGS state for replay-aware 0-RTT
- accepted 0-RTT requests and HTTP Datagrams
- clean rollback when QUIC rejects early data

## Dependencies

The release is tested against released CPAN modules:

- Alien::nghttp3 0.01
- Net::QUIC 0.04
- Uniform::HTTP 0.04
- Perl 5.20 or newer

## Testing

The normal suite uses real kernel UDP sockets, TLS, QUIC, and HTTP/3 and is
tested on Perl 5.20, 5.28, 5.36, and 5.44.

The separate public interoperability suite has completed multiplexed streaming
HTTP/3 requests against independent Cloudflare and LiteSpeed servers.

Public-network interoperability tests remain outside the CPAN installation test
path so an unavailable external service cannot make installation flaky.

## Scope

Unblock::HTTP3 is an HTTP/3 engine, not a web framework. It does not own UDP
sockets, timers, TLS, or an event loop.

WebTransport, WebSocket over HTTP/3, and MASQUE remain separate higher-level
protocols.

HTTP/3 Server Push is not included because the libnghttp3 1.18.0 API used by
this release does not implement it.

See MISSING_FEATURES.md for deliberately deferred work and
docs/INTEROPERABILITY.md for the external interoperability suite.
