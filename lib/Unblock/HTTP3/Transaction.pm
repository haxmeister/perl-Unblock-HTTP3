package Unblock::HTTP3::Transaction;

use strict;
use warnings;

use Carp qw(croak);
use Scalar::Util qw(blessed weaken);

use Unblock::HTTP3 ();

our $VERSION = '0.01';

my %TERMINAL = map { $_ => 1 } qw(complete cancelled error);

sub _new {
    my ($class, %args) = @_;

    my $connection = delete $args{connection};
    my $stream_id  = delete $args{stream_id};
    my $request    = delete $args{request};
    my $response   = delete $args{response};

    croak 'Transaction requires a Unblock::HTTP3::Connection'
        unless blessed($connection)
            && $connection->isa('Unblock::HTTP3::Connection');
    croak 'Transaction requires a non-negative stream ID'
        unless defined($stream_id)
            && !ref($stream_id)
            && $stream_id =~ /\A[0-9]+\z/;
    croak 'Transaction requires a Unblock::HTTP3::Request'
        unless blessed($request)
            && $request->isa('Unblock::HTTP3::Request');
    croak 'Transaction response must be a Unblock::HTTP3::Response'
        if defined($response)
            && (!blessed($response)
                || !$response->isa('Unblock::HTTP3::Response'));
    croak 'unknown Transaction option: ' . join(', ', sort keys %args)
        if %args;

    my $self = bless {
        connection => $connection,
        stream_id  => 0 + $stream_id,
        request    => $request,
        response                => $response,
        informational           => [],
        request_body            => undef,
        response_body            => undef,
        request_receive_mode     => 'buffered',
        response_receive_mode    => 'buffered',
        request_receive_options  => {},
        response_receive_options => {},
        response_output_started  => 0,
        capsule_stream           => undef,
        datagrams_enabled        => 0,
        datagram_queue           => [],
        datagram_callback        => undef,
        priority                 => $request->priority,
        state                    => 'active',
        error                   => undef,
    }, $class;

    weaken($self->{connection});

    return $self;
}

sub stream_id {
    my ($self, @args) = @_;
    croak 'stream_id() does not accept arguments' if @args;
    return $self->{stream_id};
}

sub request {
    my ($self, @args) = @_;
    croak 'request() does not accept arguments' if @args;
    return $self->{request};
}

sub protocol {
    my ($self, @args) = @_;
    croak 'protocol() does not accept arguments' if @args;
    return $self->{request}->protocol;
}

sub is_extended_connect {
    my ($self, @args) = @_;
    croak 'is_extended_connect() does not accept arguments' if @args;
    return defined($self->{request}->protocol) ? 1 : 0;
}

sub response {
    my ($self, @args) = @_;
    croak 'response() does not accept arguments' if @args;
    return $self->{response};
}

sub priority {
    my ($self, @args) = @_;

    my $connection = $self->{connection};

    if (!@args) {
        return { %{ $self->{priority} } }
            if $self->is_terminal || !defined($connection);

        my $priority = $connection->_transaction_priority($self);
        $self->{priority} = { %$priority };

        return { %$priority };
    }

    croak 'priority() cannot change a terminal Transaction'
        if $self->is_terminal;

    $connection
        or croak 'priority(): Transaction no longer has a connection';

    my $current = $connection->_transaction_priority($self);
    my $priority = Unblock::HTTP3::Request::_priority_from_args(
        $current,
        @args,
    );

    $connection->_set_transaction_priority(
        $self,
        $priority,
    );

    $self->{priority} = { %$priority };
    return $self;
}

sub capsules {
    my ($self, @args) = @_;

    if (my $stream = $self->{capsule_stream}) {
        croak 'capsules() options can only be supplied when the stream is created'
            if @args;
        return $stream;
    }

    croak 'capsules() options must be key/value pairs'
        if @args % 2;
    croak 'capsules() cannot be used on a terminal Transaction'
        if $self->is_terminal;
    croak 'capsules() requires Extended CONNECT'
        unless $self->is_extended_connect;

    require Unblock::HTTP3::Capsule::Stream;

    my $stream = Unblock::HTTP3::Capsule::Stream->_new(
        $self,
        @args,
    );

    $self->{capsule_stream} = $stream;
    return $stream;
}

sub _enable_datagrams {
    my ($self) = @_;
    $self->{datagrams_enabled} = 1;
    return $self;
}

sub datagrams_enabled {
    my ($self, @args) = @_;
    croak 'datagrams_enabled() does not accept arguments' if @args;
    return $self->{datagrams_enabled} ? 1 : 0;
}

sub send_datagram {
    my ($self, $bytes) = @_;

    croak 'send_datagram(): Transaction is already terminal'
        if $self->is_terminal;
    croak 'send_datagram(): HTTP Datagrams are not enabled for this Transaction'
        unless $self->{datagrams_enabled};

    my $connection = $self->{connection}
        or croak 'send_datagram(): Transaction no longer has a connection';

    return $connection->_send_transaction_datagram($self, $bytes);
}

sub max_datagram_payload_size {
    my ($self, @args) = @_;
    croak 'max_datagram_payload_size() does not accept arguments' if @args;
    return 0 unless $self->{datagrams_enabled};
    return 0 if $self->is_terminal;

    my $connection = $self->{connection};
    return 0 unless defined $connection;

    return $connection->_transaction_datagram_payload_size($self);
}

sub next_datagram {
    my ($self, @args) = @_;
    croak 'next_datagram() does not accept arguments' if @args;

    my $bytes = shift @{ $self->{datagram_queue} };
    return unless defined $bytes;

    my $connection = $self->{connection};
    $connection->_datagram_dequeued(length($bytes))
        if defined $connection;

    return $bytes;
}

sub on_datagram {
    my ($self, $callback) = @_;

    croak 'on_datagram() callback must be a code reference or undef'
        if defined($callback) && ref($callback) ne 'CODE';

    $self->{datagram_callback} = $callback;

    if (defined $callback) {
        while (defined(my $bytes = $self->next_datagram)) {
            $callback->($self, $bytes);
        }
    }

    return $self;
}

sub _enqueue_datagram {
    my ($self, $bytes) = @_;
    push @{ $self->{datagram_queue} }, $bytes;
    return;
}

sub _receive_datagram {
    my ($self, $bytes) = @_;

    my $callback = $self->{datagram_callback};
    if (defined $callback) {
        $callback->($self, $bytes);
        return;
    }

    my $connection = $self->{connection};
    return unless defined $connection;

    $connection->_buffer_transaction_datagram($self, $bytes);
    return;
}

sub _discard_datagrams {
    my ($self) = @_;

    my $connection = $self->{connection};

    if (defined $connection) {
        for my $bytes (@{ $self->{datagram_queue} }) {
            $connection->_datagram_dequeued(length($bytes));
        }
    }

    $self->{datagram_queue} = [];
    $self->{datagram_callback} = undef;
    return;
}

sub state {
    my ($self, @args) = @_;
    croak 'state() does not accept arguments' if @args;
    return $self->{state};
}

sub error {
    my ($self, @args) = @_;
    croak 'error() does not accept arguments' if @args;
    return $self->{error};
}

sub is_complete {
    my ($self, @args) = @_;
    croak 'is_complete() does not accept arguments' if @args;
    return $self->{state} eq 'complete' ? 1 : 0;
}

sub is_cancelled {
    my ($self, @args) = @_;
    croak 'is_cancelled() does not accept arguments' if @args;
    return $self->{state} eq 'cancelled' ? 1 : 0;
}

sub is_terminal {
    my ($self, @args) = @_;
    croak 'is_terminal() does not accept arguments' if @args;
    return $TERMINAL{ $self->{state} } ? 1 : 0;
}

sub next_informational {
    my ($self, @args) = @_;

    croak 'next_informational() does not accept arguments' if @args;
    return shift @{ $self->{informational} };
}

sub send_informational {
    my ($self, $response) = @_;

    croak 'send_informational(): Transaction is already terminal'
        if $self->is_terminal;
    croak 'send_informational(): response must be a Unblock::HTTP3::Response'
        unless blessed($response)
            && $response->isa('Unblock::HTTP3::Response');
    croak 'send_informational(): status must be 100 through 199, excluding 101'
        unless $response->status >= 100
            && $response->status <= 199
            && $response->status != 101;
    croak 'send_informational(): informational responses cannot have a body'
        if $response->has_buffered_body
            || $response->_has_incremental_body;
    croak 'send_informational(): informational responses cannot have trailers'
        if $response->has_trailers;

    my $connection = $self->{connection}
        or croak 'send_informational(): Transaction no longer has a connection';

    $connection->_send_informational_response(
        $self,
        $response,
    );

    return $self;
}

sub is_response_started {
    my ($self, @args) = @_;
    croak 'is_response_started() does not accept arguments' if @args;
    return $self->{response_output_started} ? 1 : 0;
}

sub request_body {
    my ($self, @args) = @_;

    if (my $body = $self->{request_body}) {
        if (@args) {
            croak 'request_body options must be key/value pairs'
                if @args % 2;

            if ($body->can('_configure')) {
                $body->_configure(@args);
            } else {
                croak 'request_body options may only be supplied when the producer is created';
            }
        }

        return $body;
    }

    croak 'request_body(): Transaction is already terminal'
        if $self->is_terminal;

    my $connection = $self->{connection}
        or croak 'request_body(): Transaction no longer has a connection';

    if ($connection->role eq 'server') {
        croak 'request_body(): request receive mode is buffered'
            unless $self->{request_receive_mode} eq 'stream';
        croak 'request_body options must be key/value pairs'
            if @args % 2;

        require Unblock::HTTP3::Body::Reader;

        my %option = (
            %{ $self->{request_receive_options} || {} },
            @args,
        );

        my $body = Unblock::HTTP3::Body::Reader->_new(
            $self,
            'request',
            %option,
        );

        $self->{request_body} = $body;
        return $body;
    }

    my $request = $self->{request};

    croak 'request_body(): Request is not configured for incremental body production'
        unless $request->_has_incremental_body;
    croak 'request_body options must be key/value pairs'
        if @args % 2;

    require Unblock::HTTP3::Body::Stream;

    my $body = Unblock::HTTP3::Body::Stream->_new(
        $self,
        'request',
        @args,
    );

    $self->{request_body} = $body;
    return $body;
}

sub response_body {
    my ($self, @args) = @_;

    if (my $body = $self->{response_body}) {
        if (@args) {
            croak 'response_body options must be key/value pairs'
                if @args % 2;

            if ($body->can('_configure')) {
                $body->_configure(@args);
            } else {
                croak 'response_body options may only be supplied when the producer is created';
            }
        }

        return $body;
    }

    croak 'response_body(): Transaction is already terminal'
        if $self->is_terminal;

    my $connection = $self->{connection}
        or croak 'response_body(): Transaction no longer has a connection';

    if ($connection->role eq 'client') {
        croak 'response_body(): response receive mode is buffered'
            unless $self->{response_receive_mode} eq 'stream';
        croak 'response_body options must be key/value pairs'
            if @args % 2;

        require Unblock::HTTP3::Body::Reader;

        my %option = (
            %{ $self->{response_receive_options} || {} },
            @args,
        );

        my $body = Unblock::HTTP3::Body::Reader->_new(
            $self,
            'response',
            %option,
        );

        $self->{response_body} = $body;
        return $body;
    }

    croak 'response_body(): response output has already started'
        if $self->{response_output_started};
    croak 'response_body options must be key/value pairs'
        if @args % 2;

    my $response = $self->{response}
        or croak 'response_body(): Transaction has no Response';

    $connection->_assert_response_body_allowed(
        $self,
        $response,
        'response_body()',
    );

    $response->_begin_stream_body;

    require Unblock::HTTP3::Body::Stream;

    my $body = Unblock::HTTP3::Body::Stream->_new(
        $self,
        'response',
        @args,
    );

    $self->{response_body} = $body;
    return $body;
}

sub send_response {
    my ($self) = @_;

    croak 'send_response(): Transaction is already terminal'
        if $self->is_terminal;

    my $connection = $self->{connection}
        or croak 'send_response(): Transaction no longer has a connection';

    my $response = $self->{response}
        or croak 'send_response(): Transaction has no Response';

    croak 'send_response(): Response has an incremental body; use response_body()'
        if $response->_has_incremental_body;

    $connection->_send_transaction_response($self);
    return $self;
}

sub cancel {
    my ($self) = @_;

    return $self if $self->is_terminal;

    my $connection = $self->{connection};
    if (defined $connection) {
        $connection->_cancel_transaction($self);
    }

    return $self if $self->is_terminal;
    return $self->_mark_cancelled;
}

sub _configure_receive_body {
    my ($self, $kind, $mode, $options) = @_;

    croak "unsupported HTTP body receive kind '$kind'"
        if $kind ne 'request' && $kind ne 'response';
    croak 'receive body mode must be buffered or stream'
        if $mode ne 'buffered' && $mode ne 'stream';
    croak 'receive body options must be a hash reference'
        unless ref($options) eq 'HASH';

    $self->{ $kind . '_receive_mode' } = $mode;
    $self->{ $kind . '_receive_options' } = { %$options };

    return $self;
}

sub _ensure_receive_reader {
    my ($self, $kind) = @_;

    return unless $self->{ $kind . '_receive_mode' } eq 'stream';

    return $kind eq 'request'
        ? $self->request_body
        : $self->response_body;
}

sub _incoming_body_reader {
    my ($self, $kind) = @_;

    return unless $self->{ $kind . '_receive_mode' } eq 'stream';

    return $self->_ensure_receive_reader($kind);
}

sub _consume_received_body {
    my ($self, $kind, $amount) = @_;

    my $connection = $self->{connection}
        or croak 'received body lost its HTTP/3 connection';

    $connection->_consume_received_body(
        $self,
        $kind,
        $amount,
    );

    return;
}

sub _received_body_complete {
    my ($self, $kind) = @_;

    my $connection = $self->{connection};
    $connection->_maybe_complete_transaction($self->{stream_id})
        if defined $connection;

    return;
}

sub _capsule_protocol_error {
    my ($self, $error) = @_;

    return if $self->is_terminal;

    my $connection = $self->{connection};
    if (defined $connection) {
        $connection->_capsule_protocol_error(
            $self,
            $error,
        );
    } else {
        $self->_mark_error($error);
    }

    return;
}

sub _write_body {
    my ($self, $kind, $bytes, $final, $operation) = @_;

    croak "$operation(): Transaction is already terminal"
        if $self->is_terminal;
    croak "$operation(): unsupported HTTP body producer '$kind'"
        if $kind ne 'request' && $kind ne 'response';

    my $message = $kind eq 'request'
        ? $self->{request}
        : ($self->{response}
            or croak "$operation(): Transaction has no Response");

    my $connection = $self->{connection}
        or croak "$operation(): Transaction no longer has a connection";

    my ($can_continue, $ok, $error);

    {
        local $@;
        $ok = eval {
            $can_continue = $connection->_write_transaction_body(
                $self,
                $kind,
                $bytes,
                $final,
                $operation,
            );
            1;
        };
        $error = $@;
    }

    die $error unless $ok;

    $message->_mark_complete if $final;
    return $can_continue;
}

sub _request_body_object {
    my ($self) = @_;
    return $self->{request_body};
}

sub _response_body_object {
    my ($self) = @_;
    return $self->{response_body};
}

sub _mark_response_started {
    my ($self) = @_;
    $self->{response_output_started} = 1;
    return $self;
}

sub _cancel_body_producers {
    my ($self) = @_;

    if (my $body = $self->{request_body}) {
        $body->_cancel unless $body->is_complete;
    }

    if (my $body = $self->{response_body}) {
        $body->_cancel unless $body->is_complete;
    }

    return;
}

sub _push_informational {
    my ($self, $response) = @_;

    croak 'informational response must be a Unblock::HTTP3::Response'
        unless blessed($response)
            && $response->isa('Unblock::HTTP3::Response');

    push @{ $self->{informational} }, $response;
    return $response;
}

sub _set_response {
    my ($self, $response) = @_;

    croak 'cannot attach a response to a terminal Transaction'
        if $self->is_terminal;
    croak 'Transaction already has a response'
        if defined $self->{response};
    croak 'Transaction response must be a Unblock::HTTP3::Response'
        unless blessed($response)
            && $response->isa('Unblock::HTTP3::Response');

    $self->{response} = $response;
    return $response;
}

sub _mark_complete {
    my ($self) = @_;
    return $self if $self->is_terminal;

    $self->_cancel_body_producers;
    $self->_discard_datagrams;
    $self->{state} = 'complete';

    return $self;
}

sub _mark_cancelled {
    my ($self) = @_;
    return $self if $self->is_terminal;

    $self->_cancel_body_producers;
    $self->_discard_datagrams;
    $self->{state} = 'cancelled';

    return $self;
}

sub _mark_error {
    my ($self, $error) = @_;
    return $self if $self->is_terminal;

    $self->_cancel_body_producers;
    $self->_discard_datagrams;
    $self->{state} = 'error';
    $self->{error} = defined($error) ? "$error" : 'HTTP/3 transaction failed';

    return $self;
}

1;

__END__

=head1 NAME

Unblock::HTTP3::Transaction - one HTTP/3 request and response

=head1 DESCRIPTION

A Transaction represents one HTTP/3 request stream.

It keeps the Request, final Response, body streams, informational responses,
and cancellation state together. Applications do not need to match responses
with raw QUIC stream IDs.

=head1 METHODS

=head2 stream_id

Returns the HTTP/3 request stream ID used by this Transaction.

Applications normally do not need to use the raw stream ID.

=head2 request

Returns the L<Unblock::HTTP3::Request>.

=head2 protocol

Returns the protocol identifier for an Extended CONNECT transaction, or
C<undef> for an ordinary request or basic CONNECT tunnel.

=head2 is_extended_connect

True when the request is an Extended CONNECT request.

=head2 priority

    my $priority = $tx->priority;

    $tx->priority(
        urgency     => 0,
        incremental => 1,
    );

Returns or changes the live RFC 9218 priority for this request stream.

On a client, changing priority sends a PRIORITY_UPDATE. On a server, changing
priority overrides the client priority for local response scheduling.

Urgency is from 0 through 7, where 0 is most urgent. Incremental is 0 or 1.

=head2 response

Returns the final L<Unblock::HTTP3::Response> when one is available.

A server Transaction receives a mutable Response when the request is created.

=head2 capsules

    my $capsules = $tx->capsules;

Creates or returns a L<Unblock::HTTP3::Capsule::Stream> for an Extended CONNECT
Transaction.

Higher-level protocols remain responsible for deciding when Capsule Protocol
use has been negotiated.

=head2 datagrams_enabled

True when the higher-level HTTP extension marked this request as defining HTTP
Datagram semantics.

=head2 send_datagram

    my $accepted = $tx->send_datagram($bytes);

Sends one RFC 9297 HTTP Datagram through Net::QUIC. The Quarter Stream ID is
added automatically. A false return preserves Net::QUIC's bounded transmit
backpressure and means the caller should decide whether to retry or drop the
unreliable payload.

Both endpoints must have negotiated SETTINGS_H3_DATAGRAM and the request
stream's local send side must still be open.

=head2 next_datagram

Returns the next received HTTP Datagram payload for this Transaction, or
C<undef> when none is queued.

=head2 on_datagram

    $tx->on_datagram(sub {
        my ($tx, $bytes) = @_;
        ...
    });

Installs a callback for received HTTP Datagram payloads. Existing queued
payloads are drained to the callback.

=head2 max_datagram_payload_size

Returns the current maximum payload bytes this Transaction can send after the
Quarter Stream ID overhead is removed from Net::QUIC's current path capacity.
Returns zero when HTTP Datagrams are not currently sendable.

=head2 is_response_started

True after the final response header section has started sending.

=head2 request_body

Represents the request body.

On a client it is a writable L<Unblock::HTTP3::Body::Stream> when the request was
created with C<stream_body>.

On a server it is a readable L<Unblock::HTTP3::Body::Reader> when request receive
mode is C<stream>.

=head2 response_body

Represents the response body.

On a server it creates or returns the writable
L<Unblock::HTTP3::Body::Stream>.

On a client it returns the readable L<Unblock::HTTP3::Body::Reader> when response
receive mode is C<stream>.

=head2 send_response

Server only.

Sends the Transaction's final buffered or bodyless Response.

For an incremental response body, use C<response_body> instead.

=head2 send_informational

Server only.

    $tx->send_informational(
        Unblock::HTTP3::Response->new(
            status => 103,
            headers => [
                [ link => '</style.css>; rel=preload' ],
            ],
        ),
    );

Sends a 1xx response before the final Response. HTTP/3 does not use status
101.

=head2 next_informational

Client only.

Returns the next received informational Response for this Transaction.

=head2 cancel

Cancels the request stream with C<H3_REQUEST_CANCELLED>.

=head2 state

Returns C<active>, C<complete>, C<cancelled>, or C<error>.

=head2 error

Returns Transaction error text when C<state> is C<error>.

=head2 is_complete

=head2 is_cancelled

=head2 is_terminal

Report Transaction lifecycle state.

=cut