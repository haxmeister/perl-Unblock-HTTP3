# Missing features

Unblock::HTTP3 implements the core HTTP/3 engine needed for normal client,
server, multiplexing, streaming, CONNECT, Capsule, HTTP Datagram, RFC 9412
ORIGIN, priority, graceful shutdown, and 0-RTT use.

The RFC audit found one narrow RFC 9218 priority-parsing limitation in the
libnghttp3 1.18.0 dependency. It does not block normal priority use, but it is
recorded below because it prevents claiming perfect normative coverage.

This file records work that is deliberately deferred so it does not get lost.

## HTTP/3 Server Push

Server Push is not exposed.

The libnghttp3 1.18.0 API used by this distribution does not implement HTTP/3
Server Push. Revisit this only if the native library gains suitable support.
Unblock::HTTP3 should not build a second HTTP/3 state machine around libnghttp3
to add it.

## RFC 9218 parameter edge semantics

Normal Priority fields and PRIORITY_UPDATE are supported.

libnghttp3 1.18.0 can reject a complete priority value when a recognized
parameter has an out-of-range value or unexpected type. RFC 9218 instead
requires that parameter to be ignored while other valid parameters remain in
effect, provided the Structured Fields Dictionary itself parsed successfully.

The public libnghttp3 callbacks do not expose the raw received PRIORITY_UPDATE
value, so Unblock::HTTP3 cannot completely repair this behavior without adding
its own RFC 8941 Structured Fields parser or replacing part of native priority
processing.

Revisit this when libnghttp3 changes its parser semantics or when a suitable
small Structured Fields implementation is deliberately added.

## Arbitrary extension frames

Unblock::HTTP3 supports generic extension SETTINGS, RFC 9412 ORIGIN, Extended
CONNECT protocol identifiers, Capsule types, HTTP Datagrams, and extension
unidirectional streams.

It does not expose a general arbitrary-frame writer on request or control
streams. libnghttp3 owns framing, output offsets, and acknowledgement
accounting on those streams and does not currently provide a safe generic
submission hook.

A concrete future extension can justify a narrower hook if libnghttp3 adds an
appropriate API.

## Interoperability expansion

The interoperability suite now proves both directions:

- the Unblock::HTTP3 client against independent Cloudflare and LiteSpeed
  HTTP/3 servers
- an independent quic-go v0.63.0 client driving an Unblock::HTTP3 server over
  real loopback UDP/TLS/QUIC/HTTP/3

Google is retained as a diagnostic public target because GitHub-hosted runners
have intermittently been unable to establish QUIC to it.

Useful later additions include:

- more independently implemented public server targets
- additional independent client implementations
- scheduled interoperability runs that can surface ecosystem regressions

These should remain outside the normal CPAN test path because public network
availability must not make installation tests flaky.

## Convenience callbacks

Transaction polling is complete, but later releases may add small convenience
callbacks for terminal completion or error notification.

Any callback API should remain optional and should not replace the current
pull/state interface.

## Introspection

Possible later additions include a compact read-only view of:

- active Transaction counts
- buffered body and Datagram bytes
- current shutdown state
- all understood peer SETTINGS
- QPACK state that libnghttp3 can expose safely

Introspection should not leak native structs into the public API.

## Performance work

Repeatable HTTP/3, body, and loopback benchmarks now exist. The 0.02 work also
reduced outgoing and incoming body copies and moved canonical Uniform message
access onto FastPath.

Useful later measurements still include:

- QPACK configuration tradeoffs
- very high-concurrency request throughput
- profiling against additional independent HTTP/3 implementations

Performance changes should remain benchmark-driven rather than speculative.

## Optional GREASE generation

Unblock::HTTP3 correctly ignores peer HTTP/3 GREASE identifiers and prevents
applications from assigning them extension semantics.

A later release may also emit optional outbound GREASE SETTINGS or other
reserved protocol elements. RFC 9114 recommends this for implementation
robustness, but it is not required for protocol correctness.

## Higher-level protocols

These are not missing Unblock::HTTP3 features and should remain separate
protocol layers:

- WebTransport over HTTP/3
- WebSocket over HTTP/3
- MASQUE protocols such as CONNECT-UDP and CONNECT-IP

They can build on Extended CONNECT, Capsules, HTTP Datagrams, and extension
SETTINGS without putting their session semantics into this engine.

## Not Unblock::HTTP3 responsibilities

These remain in Net::QUIC or the application/event-loop integration layer:

- UDP socket ownership
- TLS ownership
- QUIC packet processing
- congestion control
- retransmission
- QUIC connection migration
- QUIC transport-level 0-RTT
- timers
- event-loop ownership

Unblock::HTTP3 should remain an operating-system- and event-loop-neutral HTTP/3
protocol engine.
