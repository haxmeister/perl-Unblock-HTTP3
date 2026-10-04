# External HTTP/3 interoperability

The normal test suite is deterministic and self-contained. It uses real UDP,
TLS, QUIC, and HTTP/3, but both endpoints are controlled by this project.

The optional interoperability suite connects the Unblock::HTTP3 client to
independent public HTTP/3 implementations.

The default targets are:

- Cloudflare on www.cloudflare.com:443 - required
- LiteSpeed on litespeedtech.com:443 - required
- Google on www.google.com:443 - diagnostic

Each required target performs a real certificate-verified QUIC handshake with
ALPN h3 and then receives two concurrent HTTP/3 requests. Response bodies are
consumed through the streaming API so the test also exercises receive credit
and large-body delivery.

The release-preparation run completed both requests against Cloudflare and
LiteSpeed. The Google endpoint is diagnostic because GitHub-hosted runners have
intermittently failed to establish QUIC to it even while independent HTTP/3
checkers report the endpoint as available.

Run the suite with:

    UNBLOCK_HTTP3_PUBLIC_INTEROP=1 prove -lv xt/interop-public.t

To choose explicit required targets:

    UNBLOCK_HTTP3_PUBLIC_INTEROP=1 \
    UNBLOCK_HTTP3_INTEROP_TARGETS=example.com:443,other.example:4433 \
    prove -lv xt/interop-public.t

Public endpoints can be unavailable, rate limited, reconfigured, or blocked by
the local network. For that reason this suite is not part of make test and is
not allowed to make CPAN installation tests flaky.

The GitHub public-http3-interop workflow can run the suite manually. It also
runs when the interoperability test or its workflow definition changes.

A later interoperability expansion can test the opposite direction with an
independent external HTTP/3 client driving an Unblock::HTTP3 server. That work
is tracked in MISSING_FEATURES.md.
