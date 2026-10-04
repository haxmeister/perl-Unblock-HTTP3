# Unblock::HTTP3

[![CPAN version](https://badge.fury.io/pl/Unblock-HTTP3.svg)](https://metacpan.org/dist/Unblock-HTTP3)
[![CPANTS Kwalitee](https://cpants.cpanauthors.org/dist/Unblock-HTTP3.svg)](https://cpants.cpanauthors.org/dist/Unblock-HTTP3)
[![CI](https://github.com/haxmeister/perl-Unblock-HTTP3/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/haxmeister/perl-Unblock-HTTP3/actions/workflows/test.yml)
[![License](https://img.shields.io/cpan/l/Unblock-HTTP3.svg)](https://github.com/haxmeister/perl-Unblock-HTTP3/blob/main/LICENSE)
[![Perl](https://img.shields.io/badge/perl-5.20%2B-blue.svg)](https://www.perl.org/)
[![nghttp3](https://img.shields.io/badge/nghttp3-1.18.0-blue.svg)](https://github.com/ngtcp2/nghttp3)
[![HTTP/3](https://img.shields.io/badge/HTTP%2F3-RFC%209114-blue.svg)](https://www.rfc-editor.org/rfc/rfc9114)

Unblock::HTTP3 is an HTTP/3 engine for Perl.

It sits above Net::QUIC and below higher-level HTTP libraries.

    application or HTTP library
            |
        Unblock::HTTP3
            |
        Net::QUIC
            |
            UDP

Unblock::HTTP3 uses libnghttp3 through Alien::nghttp3 for HTTP/3 framing and
QPACK. Net::QUIC supplies QUIC transport and TLS.

Unblock::HTTP3 is designed to remain operating-system and event-loop neutral. It does not own UDP sockets, timers, TLS, or
an event loop.

Request and response objects follow the Uniform::HTTP message contract so
HTTP/3 can use the same HTTP-facing conventions as Linux::Event::HTTP.

## Installation

From CPAN:

    cpanm Unblock::HTTP3

Alien::nghttp3 supplies libnghttp3 and Net::QUIC supplies QUIC transport.

## Status

The core HTTP/3 path is working.

Unblock::HTTP3 supports:

- establish HTTP/3 over a real Net::QUIC connection
- create the required control and QPACK streams
- send and receive requests and responses
- keep multiplexed responses paired with the correct request
- send and receive 1xx informational responses
- use buffered request and response bodies
- stream outgoing request and response bodies with backpressure
- stream incoming request and response bodies without buffering them
- send and receive trailers
- validate HTTP/3 field rules, routing fields, and Content-Length
- enforce bodyless response rules
- support basic and generic Extended CONNECT tunnels
- frame, parse, send, and receive generic RFC 9297 Capsules
- negotiate, route, send, and receive RFC 9297 HTTP Datagrams
- cancel requests and handle RESET_STREAM and STOP_SENDING
- apply bounded output and receive buffering
- limit decoded field sections and message bodies
- honor the peer's SETTINGS_MAX_FIELD_SECTION_SIZE before sending fields
- advertise, inspect, and validate generic HTTP/3 extension SETTINGS
- open and dispatch generic HTTP/3 extension unidirectional streams
- set and update RFC 9218 request priorities
- configure QPACK table and blocked-stream limits
- begin graceful HTTP/3 shutdown
- clean up completed stream and native body state
- close QUIC cleanly when libnghttp3 reports a fatal parser error

The real integration tests use kernel UDP sockets and a real QUIC/TLS
handshake.

## Main objects

One HTTP/3 connection wraps one Net::QUIC::Connection:

    my $h3 = Unblock::HTTP3::Connection->client(
        quic => $quic,
    );

On servers, Unblock::HTTP3 mirrors Net::QUIC 0.04's default of 100 initial peer
bidirectional streams into libnghttp3. If the QUIC server was configured with a
different `transport->{max_bidi_streams}` value, pass the same value as
`quic_max_bidi_streams` when constructing the HTTP/3 server connection.
This keeps libnghttp3's request-ID validation synchronized with QUIC; Net::QUIC
still owns the actual stream limit and MAX_STREAMS transport behavior.

A client request returns a Transaction:

    my $tx = $h3->request($request);

A server receives Transactions with:

    my $tx = $h3->next_transaction;

The Transaction owns the request, response, body streams, cancellation state,
and informational responses for one HTTP/3 request stream.

## Request priority

RFC 9218 priority is available on Request and Transaction objects.

Set the initial request priority with:

    $request->priority(
        urgency     => 1,
        incremental => 1,
    );

Urgency ranges from 0 through 7, where 0 is most urgent.

After the request is active, use:

    $tx->priority(
        urgency     => 0,
        incremental => 0,
    );

A client Transaction sends PRIORITY_UPDATE. A server Transaction can inspect
the effective client priority or override it for local response scheduling.

## Body handling

Buffered bodies are the default.

For an outgoing streaming body, use the Transaction body producer. `write`
returns false when production should pause until `on_drain` runs.

Incoming bodies can be switched to streaming mode. In streaming mode DATA is
not copied into the Request or Response body. QUIC receive credit is returned
only when the application consumes each chunk.

## CONNECT

Basic HTTP CONNECT tunnels are supported.

A basic CONNECT request uses authority form and omits scheme and path on the
wire. After a successful 2xx response, DATA on the request stream is tunnel
data.

Generic Extended CONNECT is also supported. A server enables it with:

    enable_extended_connect => 1

A client can inspect `peer_extended_connect_enabled` before sending an
Extended CONNECT request. Set `protocol` on the Request to add the
`:protocol` pseudo-header. The Transaction exposes the same protocol
identifier.

Unblock::HTTP3 does not assign meaning to protocol identifiers. Higher-level
protocol modules or applications decide which protocols they support.

RFC 9297 Capsule Protocol is available through `Transaction->capsules` on an
Extended CONNECT Transaction. Capsules use the existing streaming body path,
including backpressure and receive-credit handling. Capsule type semantics stay
in the higher-level protocol.

CONNECT tunnel data uses streaming body objects in both directions. A rejected
CONNECT remains an ordinary HTTP response.

## HTTP message correctness

Unblock::HTTP3 validates outgoing HTTP/3 fields before handing them to libnghttp3.

Request routing checks include:

- Host must match :authority when both are present
- http/https paths must be absolute, except OPTIONS *
- URI fragments are not allowed in :path
- http/https authority does not allow userinfo
- CONNECT requires an explicit host and port
- CONNECT ports must be from 1 through 65535

Malformed received routing fields reject only the affected request stream with
H3_MESSAGE_ERROR. Other multiplexed request streams remain usable.

It also checks:

- bodyless response rules for HEAD, 204, 205, and 304
- Content-Length syntax and duplicate fields
- buffered Content-Length mismatches
- incremental Content-Length overshoot and undershoot
- successful CONNECT responses, which must not carry Content-Length
- Content-Length and Host are rejected in trailers

libnghttp3 validates received Content-Length against received DATA.

## Scope

The initial release focuses on the HTTP/3 core needed for normal client,
server, streaming, multiplexing, shutdown, and CONNECT use.

Extensible HTTP/3 SETTINGS support is implemented as a small generic API so
higher-level protocols can advertise and inspect their own SETTINGS without
putting their semantics into Unblock::HTTP3::Connection.
HTTP/3-reserved identifiers cannot be used for extension semantics, and
GREASE setting identifiers are kept non-semantic as required by HTTP/3.

Generic HTTP/3 extension unidirectional streams can be registered with
`extension_stream_handler` and opened with `open_extension_stream`.
Unblock::HTTP3 handles the stream-type prefix while the extension owns the bytes
that follow it.

Extended CONNECT is implemented generically on top of the SETTINGS support.

Capsule Protocol support is implemented generically on Extended CONNECT data
streams.

HTTP Datagrams from RFC 9297 are implemented on top of Net::QUIC 0.04.

Enable QUIC DATAGRAM transport when creating the Net::QUIC endpoint, then opt the
HTTP/3 connection into SETTINGS_H3_DATAGRAM:

    my $h3 = Unblock::HTTP3::Connection->client(
        quic                  => $quic,
        enable_http_datagrams => 1,
    );

A client marks a request as having HTTP Datagram semantics when it creates the
Transaction:

    my $tx = $h3->request(
        $request,
        datagrams => 1,
    );

Servers use the protocol-neutral `datagram_request` predicate to decide whether
an incoming request defines HTTP Datagram semantics. The Transaction then owns
`send_datagram`, `next_datagram`, `on_datagram`, and
`max_datagram_payload_size`.

Unblock::HTTP3 handles SETTINGS_H3_DATAGRAM, Quarter Stream IDs, bounded receive
buffering, and H3_DATAGRAM_ERROR. Higher-level protocols still define what the
payload bytes mean.

HTTP Datagram 0-RTT is intentionally not enabled yet. Net::QUIC exposes the
transport capability, but Unblock::HTTP3 does not currently persist and validate
the HTTP/3 SETTINGS state required for safe RFC 9297 0-RTT use.

libnghttp3 1.18.0 does not implement HTTP/3 Server Push, so Unblock::HTTP3 does
not expose Server Push.

WebTransport is not a missing Unblock::HTTP3 feature. It is a higher-level
protocol which can be built above the generic HTTP/3 extension facilities
provided here.

See [MISSING_FEATURES.md](MISSING_FEATURES.md) for the detailed roadmap.

## CPAN dependency policy

The dependency baseline is made from released CPAN modules:

    Alien::nghttp3 0.01
    Net::QUIC      0.04
    Uniform::HTTP  0.02

CI installs these modules from CPAN.

Unblock::HTTP3 integration tests do not install Net::QUIC from GitHub. This keeps
the tested stack equal to what a CPAN user can install.

## Native dependency

Alien::nghttp3 supplies libnghttp3.

## Architecture

See docs/ARCHITECTURE.md.

## License

MIT.