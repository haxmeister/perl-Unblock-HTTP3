package Unblock::HTTP3::Request;

use strict;
use warnings;
use Carp qw(croak);
use parent 'Unblock::HTTP3::_Message';

use Unblock::HTTP3 ();
use Unblock::HTTP3::_Native ();

our $VERSION = '0.01';

sub _priority_from_args {
    my ($current, @args) = @_;

    croak 'priority() requires named arguments'
        if @args % 2;

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

    croak 'method is required' unless exists $args{method};
    croak 'target is required' unless exists $args{target};

    my $method = delete $args{method};
    my $target = delete $args{target};

    my $has_scheme = exists $args{scheme};
    my $scheme = delete $args{scheme};

    my $has_authority = exists $args{authority};
    my $authority = delete $args{authority};

    my $has_protocol = exists $args{protocol};
    my $protocol = delete $args{protocol};

    my $priority = exists $args{priority}
        ? delete $args{priority}
        : undef;

    croak 'priority must be a hash reference'
        if defined($priority) && ref($priority) ne 'HASH';

    $method = Unblock::HTTP3::_Message::_byte_string('method', $method);
    croak 'method must be an HTTP token'
        unless $method =~ /\A[!\#\$%&'*+\-.\^_\x60|~0-9A-Za-z]+\z/;

    $target = Unblock::HTTP3::_Message::_byte_string('target', $target);
    croak 'target must not be empty' unless length $target;
    croak 'target must not contain spaces or control bytes'
        if $target =~ /[\x00-\x20\x7f]/;

    if ($has_scheme && defined $scheme) {
        $scheme = Unblock::HTTP3::_Message::_byte_string('scheme', $scheme);
        croak 'invalid request scheme'
            unless $scheme =~ /\A[A-Za-z][A-Za-z0-9+.-]*\z/;
    }

    if ($has_authority && defined $authority) {
        $authority = Unblock::HTTP3::_Message::_byte_string(
            'authority',
            $authority,
        );

        croak 'invalid request authority'
            if $authority eq '' || $authority =~ /[\x00-\x20\x7f\/?#]/;
    }

    if ($has_protocol && defined $protocol) {
        $protocol = Unblock::HTTP3::_Message::_byte_string(
            'protocol',
            $protocol,
        );

        croak 'protocol must be an HTTP token'
            unless $protocol =~ /\A[!\#\$%&'*+\-.\^_\x60|~0-9A-Za-z]+\z/;
        croak 'protocol is only valid with CONNECT'
            unless $method eq 'CONNECT';
    }

    my $self = $class->_new_message(%args);
    $self->{method} = $method;
    $self->{target} = $target;
    $self->{scheme} = $scheme if $has_scheme;
    $self->{authority} = $authority if $has_authority;
    $self->{protocol} = $protocol if $has_protocol;

    $self->priority(%$priority)
        if defined $priority;

    return $self;
}

sub method {
    my ($self, @args) = @_;
    return $self->{method} unless @args;

    croak 'method() accepts at most one value' unless @args == 1;

    $self->_assert_mutable;

    my $method = Unblock::HTTP3::_Message::_byte_string('method', $args[0]);
    croak 'method must be an HTTP token'
        unless $method =~ /\A[!\#\$%&'*+\-.\^_\x60|~0-9A-Za-z]+\z/;
    croak 'method cannot change away from CONNECT while protocol is set'
        if $method ne 'CONNECT' && defined $self->{protocol};

    $self->{method} = $method;
    return $self;
}

sub protocol {
    my ($self, @args) = @_;
    return $self->{protocol} unless @args;

    croak 'protocol() accepts at most one value' unless @args == 1;

    $self->_assert_mutable;

    if (!defined $args[0]) {
        $self->{protocol} = undef;
        return $self;
    }

    croak 'protocol is only valid with CONNECT'
        unless $self->{method} eq 'CONNECT';

    my $protocol = Unblock::HTTP3::_Message::_byte_string(
        'protocol',
        $args[0],
    );

    croak 'protocol must be an HTTP token'
        unless $protocol =~ /\A[!\#\$%&'*+\-.\^_\x60|~0-9A-Za-z]+\z/;

    $self->{protocol} = $protocol;
    return $self;
}

sub priority {
    my ($self, @args) = @_;

    my $current = _parse_priority_field(
        $self->header('priority'),
    );

    return $current unless @args;

    $self->_assert_mutable;

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

sub target {
    my ($self, @args) = @_;
    return $self->{target} unless @args;

    croak 'target() accepts at most one value' unless @args == 1;

    $self->_assert_mutable;

    my $target = Unblock::HTTP3::_Message::_byte_string('target', $args[0]);
    croak 'target must not be empty' unless length $target;
    croak 'target must not contain spaces or control bytes'
        if $target =~ /[\x00-\x20\x7f]/;

    $self->{target} = $target;
    return $self;
}

sub target_is_exact {
    my ($self, @args) = @_;
    croak 'target_is_exact() does not accept arguments' if @args;
    return 1;
}

sub scheme {
    my ($self, @args) = @_;
    return $self->{scheme} unless @args;

    croak 'scheme() accepts at most one value' unless @args == 1;

    $self->_assert_mutable;

    if (!defined $args[0]) {
        $self->{scheme} = undef;
        return $self;
    }

    my $scheme = Unblock::HTTP3::_Message::_byte_string('scheme', $args[0]);
    croak 'invalid request scheme'
        unless $scheme =~ /\A[A-Za-z][A-Za-z0-9+.-]*\z/;

    $self->{scheme} = $scheme;
    return $self;
}

sub authority {
    my ($self, @args) = @_;
    return $self->{authority} unless @args;

    croak 'authority() accepts at most one value' unless @args == 1;

    $self->_assert_mutable;

    if (!defined $args[0]) {
        $self->{authority} = undef;
        return $self;
    }

    my $authority = Unblock::HTTP3::_Message::_byte_string(
        'authority',
        $args[0],
    );

    croak 'invalid request authority'
        if $authority eq '' || $authority =~ /[\x00-\x20\x7f\/?#]/;

    $self->{authority} = $authority;
    return $self;
}

1;

__END__

=head1 NAME

Unblock::HTTP3::Request - HTTP/3 request message

=head1 DESCRIPTION

Unblock::HTTP3::Request follows the Uniform::HTTP request message contract while
remaining a Unblock::HTTP3 class suitable for live HTTP/3 protocol state.

HTTP/3 scheme and authority pseudo-fields are available through C<scheme> and
C<authority>. Extended CONNECT requests also expose the C<:protocol>
pseudo-header through C<protocol>.

=cut