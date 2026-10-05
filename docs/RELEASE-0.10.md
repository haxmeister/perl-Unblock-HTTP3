# Unblock::HTTP3 0.10

Unblock::HTTP3 0.10 is a deliberate breaking API cleanup that aligns the
HTTP/3 engine with the released Unblock::HTTP1 and Unblock::HTTP2 interfaces.

## Highlights

- Add Unblock::HTTP3::Client and Unblock::HTTP3::Server with new().
- Use the common Transaction API: respond(), write(), end(), and
  send_informational().
- Add the shared lifecycle methods state(), error(), is_complete(),
  is_cancelled(), is_error(), and is_terminal().
- Add H1/H2-style client and server callbacks.
- Accept stream_body => 1 for the common streaming-body case.
- Keep Body::Stream and Body::Reader as the advanced HTTP/3 body APIs.
- Accept the portable Uniform HTTP message contract.
- Keep exact canonical Uniform::HTTP objects on the native fast path.
- Normalize NativeABI discovery with definition(), native_include_dir(),
  header_path(), and c_header().
- Use respond in the installed native consumer header as well as the Perl API.

## Breaking changes

The older HTTP/3 construction and response APIs are removed.

These no longer exist:

    Unblock::HTTP3::Connection->client()
    Unblock::HTTP3::Connection->server()
    Transaction->send_response()

Use:

    Unblock::HTTP3::Client->new()
    Unblock::HTTP3::Server->new()
    Transaction->respond()

There are no compatibility aliases.

The common stream_body option is now a boolean switch. Advanced body behavior
belongs on Body::Stream and Body::Reader.

The native consumer header also renames its final-response operation from
send_response to respond. The operations-table layout is unchanged.

## Uniform HTTP

Exact canonical Uniform::HTTP::Request and Uniform::HTTP::Response objects use
the native fast path.

Uniform-compatible subclasses and adapters use the portable Perl contract.

This keeps the public HTTP object model portable while retaining the optimized
path for native integrations.

## HTTP/3-specific APIs

HTTP/3-specific features remain unchanged in purpose and keep their protocol
names, including:

- HTTP Datagrams
- Capsules
- Extended CONNECT
- priorities
- QPACK state
- 0-RTT
- RESET_STREAM
- STOP_SENDING
- graceful shutdown

## Validation

Release preparation passed:

- Perl 5.20, 5.28, 5.36, and 5.44 test matrix
- disttest
- POD syntax checks
- staged installation
- installed NativeABI header verification
- external C compilation against the installed NativeABI header
- real UDP, TLS, QUIC, and HTTP/3 loopback tests
- public HTTP/3 interoperability
- independent quic-go client interoperability
- loopback, split-process, HTTP/3, streaming-body, and receive-body benchmarks

## Dependencies

- Perl 5.20 or newer
- Alien::nghttp3 0.01 or newer
- Net::QUIC 0.04 or newer
- Uniform::HTTP 0.06 or newer

## Compatibility

This release intentionally breaks the earlier 0.03 application API in order to
make Unblock::HTTP1, Unblock::HTTP2, and Unblock::HTTP3 feel like one family.

Net::QUIC continues to own QUIC and TLS. Unblock::HTTP3 continues to own HTTP/3
protocol state only.

WebTransport, WebSocket over HTTP/3, and MASQUE remain higher-level protocols.
