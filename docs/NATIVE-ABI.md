# Native consumer ABI

Unblock::HTTP3 provides an optional native consumer ABI for XS event frameworks
and HTTP libraries.

The ordinary Perl API remains the portable interface.

## Purpose

The native ABI removes repeated Perl method lookup from the common integration
path while keeping the normal Unblock::HTTP3 objects and semantics.

A native consumer can:

- keep one persistent context for an Unblock::HTTP3::Connection
- service the Connection
- submit a normal client Request
- poll ready Transactions
- poll informational response events
- access canonical Uniform Request and Response objects directly
- read Transaction stream ID and state
- send normal and informational server responses
- inspect Connection failure state

The ABI does not expose libnghttp3 structures.

It also does not replace the QUIC transport boundary. Net::QUIC continues to
own QUIC, TLS, packet processing, stream transport, and transport integration.

## Discovery

Perl build code can locate the installed header with:

    use Unblock::HTTP3::NativeABI;

    my $include =
        Unblock::HTTP3::NativeABI::native_include_dir();

The header is:

    Unblock/HTTP3/NativeABI/unblock_http3_consumer.h

The operations table is available through:

    my $definition =
        Unblock::HTTP3::NativeABI::definition();

Consumers must verify both the ABI version and structure size before using the
table.

ABI version 1 is:

    UB_HTTP3_CONSUMER_ABI_VERSION 1

## Connection context

Call C<create> once for each Unblock::HTTP3::Connection.

Keep that context for the lifetime of the integration rather than creating it
for every event.

Call C<destroy> when the consumer no longer needs it.

A context belongs to one Perl interpreter and must not be shared across
ithreads.

## Transactions and Uniform objects

C<next_transaction> and C<next_informational> return normal
Unblock::HTTP3::Transaction objects.

C<transaction_request> and C<transaction_response> expose the exact canonical
Uniform::HTTP objects owned by that Transaction.

An XS consumer may pass those message objects directly to the Uniform::HTTP
0.06 native FastPath for native inspection.

No second HTTP object model is introduced.

## Ownership

These operations return owned SV pointers:

    request
    next_transaction
    next_informational
    transaction_next_informational

The consumer must mortalize or decrement those values.

These operations return borrowed SV pointers:

    transaction_request
    transaction_response
    error

Borrowed values remain valid only while their owning object remains alive and
unchanged.

## Request scope

ABI version 1 C<request> uses the normal request defaults.

Advanced request options such as incremental request-body production,
streaming response configuration, HTTP Datagram opt-in, and 0-RTT opt-in
remain available through the normal Perl API.

This keeps the first ABI small and stable instead of encoding every optional
policy surface into C.

## Fallback

A consumer that cannot use ABI version 1 should use the ordinary Perl API.

The native ABI is an optimization, not a separate required interface.
