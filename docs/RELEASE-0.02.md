# Unblock::HTTP3 0.02

Unblock::HTTP3 0.02 strengthens the HTTP/3 engine after the initial release.

## Highlights

- Use exact canonical Uniform::HTTP 0.05 Request and Response objects.
- Use Uniform::HTTP::FastPath for lower-overhead message access and trusted receive construction.
- Add RFC 9412 ORIGIN support.
- Reduce outgoing and incoming body-copy overhead.
- Add repeatable HTTP/3 and body performance benchmarks.
- Expand independent client and server interoperability coverage.
- Add a requirement-level HTTP/3 RFC conformance audit and dedicated malformed-wire tests.
- Make server 0-RTT application delivery replay-safe by default.
- Harden critical-stream, SETTINGS, Server Push, Cookie, Capsule, Extended CONNECT, and HTTP Datagram edge cases.

## RFC audit

The audit covers RFC 9114, RFC 9204, RFC 9218, RFC 9220, RFC 9297, and RFC 9412.

The detailed result is in docs/RFC-COMPLIANCE.md.

Two narrow native-library limitations remain documented:

- libnghttp3 can surface some malformed HTTP messages only as connection-fatal read errors even where RFC 9114 specifies request-stream H3_MESSAGE_ERROR.
- libnghttp3 1.18.0 does not fully preserve valid RFC 9218 parameters when another recognized priority parameter has the wrong type or is out of range.

These do not block normal HTTP/3 client or server use.

## Dependencies

- Perl 5.20 or newer
- Alien::nghttp3 0.01 or newer
- Net::QUIC 0.04 or newer
- Uniform::HTTP 0.05 or newer

## Compatibility

Server Push remains intentionally unexposed because the libnghttp3 API used by this distribution does not provide the required support.

WebTransport, WebSocket over HTTP/3, and MASQUE remain higher-level protocols rather than Unblock::HTTP3 features.
