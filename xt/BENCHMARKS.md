# HTTP/3 benchmark baseline

This directory contains development benchmarks. It is excluded from the CPAN
distribution.

The benchmark suite currently contains:

    xt/benchmark-loopback.pl
    xt/benchmark-process-loopback.pl

Both measure complete HTTP/3 requests over real loopback UDP, TLS, and QUIC.
Both endpoints use Unblock::HTTP3, while Net::QUIC provides the transport.

The first script drives client and server from one Perl process. The second
forks before either endpoint creates QUIC state, so client and server have
separate Perl heaps, XS state, sockets, timers, and event-driving loops.

These are end-to-end engine benchmarks. They are not pure libnghttp3 or QPACK
microbenchmarks.

## Run it

Build the distribution first, then run either benchmark:

    perl -Iblib/lib -Iblib/arch xt/benchmark-loopback.pl
    perl -Iblib/lib -Iblib/arch xt/benchmark-process-loopback.pl

Environment variables control the workload:

    UNBLOCK_HTTP3_BENCH_REQUESTS=2000
    UNBLOCK_HTTP3_BENCH_WARMUP=200
    UNBLOCK_HTTP3_BENCH_BODY_BYTES=1024
    UNBLOCK_HTTP3_BENCH_CONCURRENCY=1,16,64

Each benchmark creates a fresh QUIC/HTTP/3 connection for every concurrency
level, warms it up, and then measures the requested batch. TLS/QUIC handshake
time and HTTP/3 SETTINGS startup are excluded from the timed interval.

The split-process result is especially useful for deciding whether a throughput
limit is caused by HTTP/3 work itself or by making one Perl interpreter drive
both endpoints serially.

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
