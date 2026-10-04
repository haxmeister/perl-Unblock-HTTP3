# Contributing

Contributions are welcome.

## Development setup

Install the released dependencies from CPAN, then build normally:

    cpanm --installdeps .
    perl Makefile.PL
    make
    make test

Unblock::HTTP3 is tested against released CPAN versions of Net::QUIC and
Alien::nghttp3. Do not replace those dependencies with Git checkouts when
testing a release.

## Project scope

Unblock::HTTP3 is an operating-system- and event-loop-neutral HTTP/3 engine.

Keep UDP sockets, timers, TLS ownership, and event-loop code outside this
distribution. Those belong below Unblock::HTTP3.

Please keep public APIs simple and avoid exposing libnghttp3 details unless
there is a strong reason.

## Tests

New protocol behavior should include tests.

Changes that affect QUIC integration should be exercised through the real
loopback test when practical.

## Style

Keep documentation direct and easy to read.

Code and POD should use ASCII text.
