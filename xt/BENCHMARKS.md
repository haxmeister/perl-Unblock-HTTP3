# HTTP/3 benchmark baseline

This directory contains development benchmarks. It is excluded from the CPAN
distribution.

The first benchmark is:

    xt/benchmark-loopback.pl

It measures complete HTTP/3 requests over real loopback UDP, TLS, and QUIC.
Both endpoints use Unblock::HTTP3, while Net::QUIC provides the transport.

This is an end-to-end engine benchmark. It is not a pure libnghttp3 or QPACK
microbenchmark.

## Run it

Build the distribution first, then run:

    perl -Iblib/lib -Iblib/arch xt/benchmark-loopback.pl

Environment variables control the workload:

    UNBLOCK_HTTP3_BENCH_REQUESTS=2000
    UNBLOCK_HTTP3_BENCH_WARMUP=200
    UNBLOCK_HTTP3_BENCH_BODY_BYTES=1024
    UNBLOCK_HTTP3_BENCH_CONCURRENCY=1,16,64

The benchmark creates a fresh QUIC/HTTP/3 connection for each concurrency
level, warms it up, and then measures the requested batch. TLS/QUIC handshake
time and HTTP/3 SETTINGS startup are excluded from the timed interval.

Reported payload throughput counts response body bytes only. Protocol, QUIC,
UDP, TLS, and packet overhead remain part of the elapsed time.

The output also reports stream-credit stalls. When the requested application
concurrency is higher than the peer's currently available QUIC bidirectional
stream credit, Unblock::HTTP3::Connection->request returns undef. The benchmark
treats that as backpressure, services the connection, and retries after stream
credit is returned.

## What this baseline is for

Use this benchmark before and after performance changes. It gives us a stable
first measurement for:

- request throughput
- multiplexing behavior as concurrency rises
- buffered response delivery
- Perl/XS and Net::QUIC integration cost

Later microbenchmarks can isolate field construction, QPACK settings, body-copy
costs, and streaming paths once the end-to-end baseline shows where work is
worth doing.

Do not turn benchmark numbers into CI pass/fail thresholds. Shared CI runners
are noisy. The workflow stores the numbers for comparison rather than treating
them as correctness tests.
