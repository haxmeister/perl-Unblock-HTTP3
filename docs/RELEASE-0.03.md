# Unblock::HTTP3 0.03

Unblock::HTTP3 0.03 focuses on native integration and message-path performance.

## Highlights

- Require Uniform::HTTP 0.06.
- Use the Uniform native FastPath for canonical Request and Response objects.
- Keep decoded HTTP/3 header blocks native until canonical Uniform objects are constructed.
- Avoid the former Perl FastPath and temporary HTTP/3 wire-field arrays on normal outgoing messages.
- Add a public versioned native consumer ABI for XS event frameworks and HTTP libraries.
- Install a public C header for native ABI consumers.
- Preserve the existing canonical Uniform object model and HTTP/3 validation rules.

## Performance

The same-run HTTP-layer benchmark improved the complete message-to-nghttp3
pipeline from about 6.69 microseconds per request to about 3.15 microseconds per
request, roughly 2.1 times faster.

The native consumer ABI also gives XS integrations a stable way to service
HTTP/3 connections, poll Transactions, access canonical Uniform messages, and
send responses without depending on private Unblock::HTTP3 or libnghttp3
structures.

## Native ABI

The new public module is:

    Unblock::HTTP3::NativeABI

The installed header is:

    Unblock/HTTP3/NativeABI/unblock_http3_consumer.h

ABI version 1 is append-only and requires consumers to check both the ABI
version and structure size before using the operations table.

The ABI remains optional. The normal Perl API is unchanged.

## Dependencies

- Perl 5.20 or newer
- Alien::nghttp3 0.01 or newer
- Net::QUIC 0.04 or newer
- Uniform::HTTP 0.06 or newer

## Compatibility

The native ABI does not expose libnghttp3 internals and does not replace the
QUIC transport boundary. Net::QUIC continues to own QUIC and TLS.

Server Push remains intentionally unexposed because the libnghttp3 API used by
this distribution does not provide the required support.

WebTransport, WebSocket over HTTP/3, and MASQUE remain higher-level protocols.
