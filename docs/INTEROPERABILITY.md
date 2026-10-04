# External HTTP/3 interoperability

The normal test suite is deterministic and self-contained. It uses real UDP,
TLS, QUIC, and HTTP/3, but both endpoints are controlled by this project.

The optional interoperability workflow tests Unblock::HTTP3 against independent
HTTP/3 implementations in both directions.

## Unblock client to independent servers

The public-server suite connects the Unblock::HTTP3 client to:

- Cloudflare on www.cloudflare.com:443 - required
- LiteSpeed on litespeedtech.com:443 - required
- Google on www.google.com:443 - diagnostic

Each required target performs a real certificate-verified QUIC handshake with
ALPN h3 and receives two concurrent HTTP/3 requests. Response bodies are
consumed through the streaming API.

Run it with:

    UNBLOCK_HTTP3_PUBLIC_INTEROP=1 prove -lv xt/interop-public.t

To choose explicit required targets:

    UNBLOCK_HTTP3_PUBLIC_INTEROP=1 \
    UNBLOCK_HTTP3_INTEROP_TARGETS=example.com:443,other.example:4433 \
    prove -lv xt/interop-public.t

Google remains diagnostic because GitHub-hosted runners have intermittently
failed to establish QUIC to it even while the other independent servers remain
reachable.

## Independent client to Unblock server

The opposite direction uses the independent quic-go HTTP/3 implementation.

CI pins quic-go v0.63.0, starts a real Unblock::HTTP3 server on a loopback UDP
socket, and lets the quic-go client connect over TLS and QUIC with ALPN h3. The
client sends a GET request, receives a 200 response, consumes the response
body, and exits successfully.

The loopback certificate is self-signed, so the external client disables
certificate verification for this test. The TLS and QUIC handshake still occur;
the public-server suite separately exercises normal certificate verification.

Run the test locally by pointing it at a compatible quic-go example client:

    UNBLOCK_HTTP3_EXTERNAL_CLIENT=/path/to/client \
    prove -lv xt/interop-external-client.t

## Why these tests stay outside make test

External endpoints can be unavailable, rate limited, reconfigured, or blocked
by the local network. Independent client toolchains also add dependencies that
normal CPAN installation should not require.

For those reasons interoperability tests live under xt and do not make CPAN
installation tests flaky.

The GitHub interoperability workflow can run the suites manually and also runs
when the interoperability tests or workflow definition change.
