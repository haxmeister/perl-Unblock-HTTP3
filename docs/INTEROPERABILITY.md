# External HTTP/3 interoperability

The normal test suite is deterministic and self-contained. It uses real UDP,
TLS, QUIC, and HTTP/3, but both endpoints are controlled by this project.

The optional interoperability suite connects the Unblock::HTTP3 client to
independent public HTTP/3 implementations.

Current default targets are:

- Cloudflare on www.cloudflare.com:443
- Google on www.google.com:443
- LiteSpeed on http3-test.litespeedtech.com:4433

The test performs a real certificate-verified QUIC handshake with ALPN h3 and
then sends two concurrent HTTP/3 requests. Response bodies are consumed through
the streaming API so the interoperability test does not depend on page size.

Run it with:

    UNBLOCK_HTTP3_PUBLIC_INTEROP=1 prove -lv xt/interop-public.t

To choose explicit targets:

    UNBLOCK_HTTP3_PUBLIC_INTEROP=1 \
    UNBLOCK_HTTP3_INTEROP_TARGETS=example.com:443,other.example:4433 \
    prove -lv xt/interop-public.t

Public endpoints can be unavailable, rate limited, reconfigured, or blocked by
the local network. For that reason this suite is not part of make test and is
not allowed to make CPAN installation tests flaky.

The GitHub public-http3-interop workflow can run the suite manually. It also
runs when the interoperability test or its workflow definition changes.
