# Missing features

Unblock::HTTP3 0.01 implements the core HTTP/3 engine planned for the first
release. There is no known missing core feature that blocks normal client,
server, multiplexing, streaming, CONNECT, Capsule, HTTP Datagram, RFC 9412
ORIGIN, priority, graceful shutdown, or 0-RTT use.

This file records work that is deliberately deferred so it does not get lost.

## HTTP/3 Server Push

Server Push is not exposed.

The libnghttp3 1.18.0 API used by this distribution does not implement HTTP/3
Server Push. Revisit this only if the native library gains suitable support.
Unblock::HTTP3 should not build a second HTTP/3 state machine around libnghttp3
to add it.

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

The public interoperability suite currently proves the Unblock::HTTP3 client
against independent Cloudflare and LiteSpeed HTTP/3 servers. Google is retained
as a diagnostic target because GitHub-hosted runners have intermittently been
unable to establish QUIC to it.

Useful later additions include:

- an independent external HTTP/3 client driving an Unblock::HTTP3 server
- more independently implemented public server targets
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

The first release prioritizes correctness and composability.

Later benchmarking can investigate:

- Perl/XS copy counts
- field construction costs
- streaming-body copy reduction
- QPACK configuration tradeoffs
- high-concurrency request throughput

Performance changes should be driven by repeatable benchmarks rather than by
adding complexity speculatively.

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
