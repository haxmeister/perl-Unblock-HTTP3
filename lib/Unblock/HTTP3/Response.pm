package Unblock::HTTP3::Response;

use strict;
use warnings;
use Carp qw(croak);
use parent 'Unblock::HTTP3::_Message';

use Unblock::HTTP3 ();

our $VERSION = '0.01';

sub new {
    my ($class, @args) = @_;
    croak 'new() requires named arguments' if @args % 2;

    my %args = @args;
    my $status = exists $args{status} ? delete $args{status} : 200;

    my $has_reason = exists $args{reason};
    my $reason = delete $args{reason};

    _validate_status($status);

    if ($has_reason && defined $reason) {
        $reason = _validate_reason($reason);
    }

    my $self = $class->_new_message(%args);
    $self->{status} = 0 + $status;
    $self->{reason} = $reason if $has_reason;

    return $self;
}

sub status {
    my ($self, @args) = @_;
    return $self->{status} unless @args;

    croak 'status() accepts at most one value' unless @args == 1;

    $self->_assert_mutable;
    _validate_status($args[0]);
    $self->{status} = 0 + $args[0];

    return $self;
}

sub reason {
    my ($self, @args) = @_;
    return $self->{reason} unless @args;

    croak 'reason() accepts at most one value' unless @args == 1;

    $self->_assert_mutable;
    $self->{reason} = defined($args[0])
        ? _validate_reason($args[0])
        : undef;

    return $self;
}

sub _validate_status {
    my ($status) = @_;

    croak 'status must be an integer from 100 through 599'
        unless defined($status)
            && !ref($status)
            && $status =~ /\A[0-9]+\z/
            && $status >= 100
            && $status <= 599;

    return;
}

sub _validate_reason {
    my ($reason) = @_;

    my $bytes = Unblock::HTTP3::_Message::_byte_string('reason', $reason);

    croak 'reason contains a prohibited control byte'
        if $bytes =~ /[\x00-\x08\x0a-\x1f\x7f]/;

    return $bytes;
}

1;

__END__

=head1 NAME

Unblock::HTTP3::Response - HTTP/3 response message

=head1 DESCRIPTION

Unblock::HTTP3::Response follows the Uniform::HTTP response message contract while
remaining a Unblock::HTTP3 class suitable for live HTTP/3 protocol state.

HTTP/3 does not carry a reason phrase on the wire. C<reason> is retained only
for the common message contract and cross-version adaptation.

=cut