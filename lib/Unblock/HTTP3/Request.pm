package Unblock::HTTP3::Request;

use strict;
use warnings;
use Carp qw(croak);

use Uniform::HTTP::Request 0.04 ();
use parent -norequire, 'Uniform::HTTP::Request';

use Unblock::HTTP3 ();
use Unblock::HTTP3::_Native ();

our $VERSION = '0.01';

sub _priority_from_args {
    my ($current, @args) = @_;
    croak 'priority() requires named arguments' if @args % 2;

    my %priority = (
        urgency     => 3,
        incremental => 0,
        %{ $current || {} },
    );

    while (@args) {
        my $name = shift @args;
        my $value = shift @args;

        croak "unknown priority option: $name"
            if $name ne 'urgency' && $name ne 'incremental';

        if ($name eq 'urgency') {
            croak 'priority urgency must be an integer from 0 through 7'
                if !defined($value)
                    || ref($value)
                    || "$value" !~ /\A[0-7]\z/;
            $priority{urgency} = 0 + $value;
            next;
        }

        croak 'priority incremental must be 0 or 1'
            if !defined($value)
                || ref($value)
                || "$value" !~ /\A[01]\z/;
        $priority{incremental} = $value ? 1 : 0;
    }

    return \%priority;
}

sub _priority_field {
    my ($priority) = @_;
    my $value = 'u=' . $priority->{urgency};
    $value .= ', i' if $priority->{incremental};
    return $value;
}

sub _parse_priority_field {
    my ($value) = @_;

    return {
        urgency     => 3,
        incremental => 0,
    } unless defined $value;

    my $parsed = eval {
        Unblock::HTTP3::_Native->parse_priority($value);
    };

    return {
        urgency     => 3,
        incremental => 0,
    } unless defined $parsed;

    return {
        urgency     => 0 + $parsed->[0],
        incremental => $parsed->[1] ? 1 : 0,
    };
}

sub new {
    my ($class, @args) = @_;
    croak 'new() requires named arguments' if @args % 2;

    my %args = @args;
    my $priority = delete $args{priority};

    croak 'priority must be a hash reference'
        if defined($priority) && ref($priority) ne 'HASH';

    my $self = $class->SUPER::new(%args);
    $self->{_http3_reset_code} = undef;
    $self->{_http3_stop_sending_code} = undef;

    $self->priority(%$priority)
        if defined $priority;

    return $self;
}

sub priority {
    my ($self, @args) = @_;

    my $current = _parse_priority_field(
        $self->header('priority'),
    );

    return $current unless @args;

    my $priority = _priority_from_args(
        $current,
        @args,
    );

    $self->header(
        'Priority',
        _priority_field($priority),
    );

    return $self;
}

sub reset_code {
    my ($self, @args) = @_;
    croak 'reset_code() does not accept arguments' if @args;
    return $self->{_http3_reset_code};
}

sub stop_sending_code {
    my ($self, @args) = @_;
    croak 'stop_sending_code() does not accept arguments' if @args;
    return $self->{_http3_stop_sending_code};
}

sub is_aborted {
    my ($self, @args) = @_;
    croak 'is_aborted() does not accept arguments' if @args;

    return defined($self->{_http3_reset_code})
        || defined($self->{_http3_stop_sending_code})
        ? 1
        : 0;
}

sub _mark_reset {
    my ($self, $code) = @_;
    $self->{_http3_reset_code} = 0 + $code;
    $self->mark_incomplete;
    $self->freeze;
    return $self;
}

sub _mark_stop_sending {
    my ($self, $code) = @_;
    $self->{_http3_stop_sending_code} = 0 + $code;
    $self->mark_incomplete;
    $self->freeze;
    return $self;
}

1;

__END__

=head1 NAME

Unblock::HTTP3::Request - HTTP/3 request message built on Uniform::HTTP

=head1 DESCRIPTION

C<Unblock::HTTP3::Request> is a thin subclass of L<Uniform::HTTP::Request>.

Uniform::HTTP owns the common HTTP message semantics: method, target, scheme,
authority, Extended CONNECT protocol metadata, headers, trailers, buffered
body state, fidelity, mutability, and completeness.

Unblock::HTTP3 adds RFC 9218 priority convenience methods and HTTP/3 abort
diagnostics. Streaming and request-stream lifecycle remain on the Transaction.

A plain L<Uniform::HTTP::Request> can also be submitted directly to
L<Unblock::HTTP3::Connection>.

=cut
