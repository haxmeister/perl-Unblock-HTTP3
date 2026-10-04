package Unblock::HTTP3::Body::Reader;

use strict;
use warnings;

use Carp qw(croak);
use Scalar::Util qw(blessed weaken);

use Unblock::HTTP3 ();
use Unblock::HTTP3::_Bytes ();

our $VERSION = '0.01';

sub _new {
    my ($class, $transaction, $kind, %option) = @_;

    croak 'body reader kind must be request or response'
        if $kind ne 'request' && $kind ne 'response';
    croak 'body reader requires a Unblock::HTTP3::Transaction'
        unless blessed($transaction)
            && $transaction->isa('Unblock::HTTP3::Transaction');

    my $on_data   = delete $option{on_data};
    my $on_end    = delete $option{on_end};
    my $on_cancel = delete $option{on_cancel};
    my $operation = $kind . '_body';

    for my $callback (
        [ on_data   => $on_data ],
        [ on_end    => $on_end ],
        [ on_cancel => $on_cancel ],
    ) {
        croak "$operation(): $callback->[0] must be a coderef"
            if defined($callback->[1]) && ref($callback->[1]) ne 'CODE';
    }

    croak "$operation(): unknown option: " . join(', ', sort keys %option)
        if %option;

    my $self = bless {
        transaction => $transaction,
        kind        => $kind,
        queue       => [],
        pending     => 0,
        ended       => 0,
        complete    => 0,
        cancelled   => 0,
        on_data     => $on_data,
        on_end      => $on_end,
        on_cancel   => $on_cancel,
        delivering  => 0,
    }, $class;

    weaken($self->{transaction});

    return $self;
}

sub _configure {
    my ($self, %option) = @_;

    my $operation = $self->{kind} . '_body';
    my $was_complete = $self->{complete};
    my $was_cancelled = $self->{cancelled};
    my $added_on_end = 0;
    my $added_on_cancel = 0;

    for my $name (qw(on_data on_end on_cancel)) {
        next unless exists $option{$name};

        my $callback = delete $option{$name};

        croak "$operation(): $name must be a coderef"
            if defined($callback) && ref($callback) ne 'CODE';
        croak "$operation(): $name is already configured"
            if defined($self->{$name});

        $self->{$name} = $callback;
        $added_on_end = 1 if $name eq 'on_end';
        $added_on_cancel = 1 if $name eq 'on_cancel';
    }

    croak "$operation(): unknown option: " . join(', ', sort keys %option)
        if %option;

    if ($was_cancelled) {
        my $callback = $self->{on_cancel};
        $callback->($self) if $added_on_cancel && $callback;
        return $self;
    }

    if ($was_complete) {
        my $callback = $self->{on_end};
        $callback->($self) if $added_on_end && $callback;
        return $self;
    }

    $self->_deliver_callbacks;
    $self->_maybe_finish;

    return $self;
}

sub pending_bytes {
    my ($self, @args) = @_;
    croak 'pending_bytes() does not accept arguments' if @args;
    return $self->{pending};
}

sub is_complete {
    my ($self, @args) = @_;
    croak 'is_complete() does not accept arguments' if @args;
    return $self->{complete} ? 1 : 0;
}

sub is_cancelled {
    my ($self, @args) = @_;
    croak 'is_cancelled() does not accept arguments' if @args;
    return $self->{cancelled} ? 1 : 0;
}

sub next_chunk {
    my ($self, @args) = @_;

    croak 'next_chunk() does not accept arguments' if @args;
    croak 'next_chunk() cannot be called from on_data'
        if $self->{delivering};
    return if $self->{cancelled};

    my $bytes = shift @{ $self->{queue} };
    if (defined $bytes) {
        $self->{pending} -= length($bytes);

        my $transaction = $self->{transaction}
            or croak 'next_chunk(): HTTP/3 Transaction is no longer available';

        $transaction->_consume_received_body(
            $self->{kind},
            length($bytes),
        );
    }

    $self->_maybe_finish;
    return $bytes;
}

sub _push {
    my ($self, $bytes) = @_;

    return if $self->{cancelled};

    $bytes = Unblock::HTTP3::_Bytes::byte_string(
        'received body',
        $bytes,
    );

    if (length $bytes) {
        push @{ $self->{queue} }, $bytes;
        $self->{pending} += length($bytes);
    }

    $self->_deliver_callbacks;
    return;
}

sub _mark_end {
    my ($self) = @_;

    return if $self->{cancelled};

    $self->{ended} = 1;
    $self->_deliver_callbacks;
    $self->_maybe_finish;

    return;
}

sub _deliver_callbacks {
    my ($self) = @_;

    my $callback = $self->{on_data} or return;

    while (!$self->{cancelled} && @{ $self->{queue} }) {
        my $bytes = $self->{queue}[0];

        $self->{delivering} = 1;

        my ($ok, $error);
        {
            local $@;
            $ok = eval {
                $callback->($self, $bytes);
                1;
            };
            $error = $@;
        }

        $self->{delivering} = 0;

        die $error unless $ok;
        return if $self->{cancelled};

        shift @{ $self->{queue} };
        $self->{pending} -= length($bytes);

        my $transaction = $self->{transaction}
            or croak 'body callback lost its HTTP/3 Transaction';

        $transaction->_consume_received_body(
            $self->{kind},
            length($bytes),
        );
    }

    $self->_maybe_finish;
    return;
}

sub _maybe_finish {
    my ($self) = @_;

    return if $self->{complete} || $self->{cancelled};
    return unless $self->{ended};
    return if @{ $self->{queue} };

    $self->{complete} = 1;

    my $transaction = $self->{transaction};
    $transaction->_received_body_complete($self->{kind})
        if defined $transaction;

    my $callback = $self->{on_end};
    $callback->($self) if $callback;

    return;
}

sub _cancel {
    my ($self) = @_;

    return if $self->{complete} || $self->{cancelled};

    $self->{cancelled} = 1;
    $self->{queue} = [];
    $self->{pending} = 0;

    my $callback = $self->{on_cancel};
    $callback->($self) if $callback;

    return;
}

sub _drain {
    return;
}

1;

__END__

=head1 NAME

Unblock::HTTP3::Body::Reader - readable HTTP/3 body stream

=head1 DESCRIPTION

A Reader provides streaming access to an incoming HTTP/3 body without
buffering the complete body in the Request or Response object.

Polling use:

    while (defined(my $chunk = $body->next_chunk)) {
        process($chunk);
    }

Calling C<next_chunk> returns QUIC receive credit for that chunk.

Callback use:

    my $body = $tx->request_body(
        on_data => sub {
            my ($body, $chunk) = @_;
            process($chunk);
        },
        on_end => sub {
            my ($body) = @_;
            ...
        },
    );

Receive credit is returned after C<on_data> returns.

=head1 METHODS

=head2 next_chunk

Returns the next available body chunk, or undef if none is currently queued.

=head2 pending_bytes

Returns the number of queued body bytes which have not yet been consumed by
the application.

=head2 is_complete

True after the remote body has ended and all queued chunks have been consumed.

=head2 is_cancelled

True if the transaction ended before the body reader completed.

=cut