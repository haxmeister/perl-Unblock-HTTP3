# Missing features

Unblock::HTTP3 0.01 focuses on the core HTTP/3 request and response engine.

The normal HTTP/3 path is implemented, including multiplexing, streaming
bodies, trailers, informational responses, basic CONNECT tunnels, QPACK,
graceful shutdown, flow control, resource limits, and HTTP message validation.

The following work still belongs in Unblock::HTTP3.

## Extensible SETTINGS support - complete

Unblock::HTTP3 now has a small generic extension SETTINGS API.

A connection can:

- advertise additional HTTP/3 SETTINGS
- inspect peer extension SETTINGS
- validate peer extension SETTINGS with a callback
- reject invalid extension SETTINGS with H3_SETTINGS_ERROR
- reject HTTP/3-reserved setting identifiers and ignore GREASE identifiers

Core SETTINGS remain managed by Unblock::HTTP3. Extension-specific behavior stays
outside Unblock::HTTP3::Connection.

This is the foundation for Extended CONNECT and HTTP Datagrams.

## Extended CONNECT - complete

Basic CONNECT and generic Extended CONNECT are supported.

Unblock::HTTP3 now provides:

- SETTINGS_ENABLE_CONNECT_PROTOCOL negotiation
- the :protocol pseudo-header
- the Extended CONNECT pseudo-header rules
- Request and Transaction access to the selected protocol
- client and server behavior over a real HTTP/3 connection
- protocol-neutral rejection of unsupported protocols

Extended CONNECT remains generic. Unblock::HTTP3 does not hard-code WebTransport,
MASQUE, or another protocol that may use it.

## HTTP Datagrams - blocked on Net::QUIC

HTTP Datagrams from RFC 9297 are not implemented yet.

Released Net::QUIC 0.03 does not implement the standardized QUIC DATAGRAM
extension. Unblock::HTTP3 therefore cannot provide real HTTP/3 Datagrams without
duplicating transport functionality that belongs in Net::QUIC.

When Net::QUIC exposes QUIC DATAGRAM transport, Unblock::HTTP3 still needs:

- SETTINGS_H3_DATAGRAM
- mapping HTTP Datagrams to the correct HTTP request stream
- sending and receiving datagram payloads through Net::QUIC
- proper error handling and capability negotiation
- real client/server tests

Unblock::HTTP3 will not create a private UDP or QUIC DATAGRAM replacement.

## Capsule Protocol - complete

Generic Capsule Protocol support from RFC 9297 is implemented.

Unblock::HTTP3 now provides:

- Capsule type-length-value framing
- incremental parsing across arbitrary body chunks
- polling and type-dispatch receive APIs
- bounded buffering for retained Capsule values
- incremental skipping of unhandled Capsule types
- sending Capsules through Extended CONNECT data streams
- receiving Capsules through Extended CONNECT data streams
- truncated-Capsule handling using H3_MESSAGE_ERROR on the affected stream
- real client/server tests over QUIC and TLS

Capsule types remain generic. Unblock::HTTP3 does not assign WebTransport, MASQUE,
or other application semantics to them.

## Generic HTTP/3 extension surface - complete for the current native boundary

Unblock::HTTP3 now exposes reusable protocol-neutral extension primitives for:

- extension SETTINGS
- Extended CONNECT protocol identifiers
- Capsule types
- extension unidirectional stream types

Registered extension stream types are dispatched outside libnghttp3. Unknown
and GREASE stream types remain non-semantic and are discarded without failing
the HTTP/3 connection.

A general arbitrary extension-frame injection API is intentionally not exposed
with libnghttp3 1.18.0. libnghttp3 owns framing and output offsets on HTTP
request and control streams, and its public API does not provide a general
arbitrary-frame submission surface. Unblock::HTTP3 will not bypass that ownership
with a second competing HTTP/3 writer.

This is a native dependency boundary rather than unfinished plugin-framework
work. A future concrete extension can justify a narrower frame hook if
libnghttp3 gains a safe API for it, or if the hook can otherwise preserve
libnghttp3 stream state and acknowledgement accounting.

## HTTP priority controls - complete

Application-facing RFC 9218 priority controls are implemented.

Unblock::HTTP3 now provides:

- Request priority through the normal HTTP Priority field
- urgency values from 0 through 7
- the incremental flag
- RFC default handling for absent or invalid Priority fields
- client PRIORITY_UPDATE through Transaction
- server inspection of the effective client priority
- server-side priority override for local scheduling

The public API stays on Request and Transaction objects and does not expose
libnghttp3 priority structs or frame details.

## HTTP/3 Server Push

Unblock::HTTP3 does not currently support Server Push.

The libnghttp3 1.18.0 API used by this distribution does not implement HTTP/3
Server Push. This can be revisited if the native library gains suitable
support.

## Higher-level protocols built on Unblock::HTTP3

These are not missing Unblock::HTTP3 features.

They should be separate protocol layers which use the generic HTTP/3
facilities above.

Examples include:

- WebTransport over HTTP/3
- WebSocket over HTTP/3
- MASQUE protocols such as CONNECT-UDP

For example, WebTransport needs HTTP/3 features such as Extended CONNECT,
HTTP Datagrams, Capsules, and extension SETTINGS, but WebTransport session
semantics do not belong inside Unblock::HTTP3 itself.

A future stack might look like:

    Net::WebTransport
            |
        Unblock::HTTP3
            |
         Net::QUIC

## Possible later improvements

These are useful improvements, but they are not missing pieces of the core
HTTP/3 protocol implementation:

- more convenience callbacks around Transaction completion
- additional peer SETTINGS introspection
- more external interoperability tests
- performance tuning and copy reduction where benchmarks justify it

## Not Unblock::HTTP3 responsibilities

The following features belong to Net::QUIC or the application/event-loop
integration layer, not Unblock::HTTP3:

- UDP socket ownership
- TLS ownership
- QUIC packet processing
- congestion control
- retransmission
- QUIC connection migration
- QUIC 0-RTT transport support
- timers
- event-loop ownership

Unblock::HTTP3 should remain an event-loop-neutral HTTP/3 protocol engine.
