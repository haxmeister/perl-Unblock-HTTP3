package Unblock::HTTP3::_Message;

use strict;
use warnings;
use Carp qw(croak);

our $VERSION = '0.01';

sub _new_message {
    my ($class, %args) = @_;

    my $version = exists $args{version} ? delete $args{version} : '3';
    my $headers = delete $args{headers};
    my $trailers = delete $args{trailers};
    my $has_body = exists $args{body};
    my $body = delete $args{body};

    croak 'unknown message option: ' . join(', ', sort keys %args) if %args;

    my $self = bless {
        version           => undef,
        headers           => [],
        trailers          => [],
        body              => undef,
        has_buffered_body => 0,
        incremental_body  => 0,
        committed         => 0,
        complete          => 1,
        reset_code        => undef,
        stop_sending_code => undef,
    }, $class;

    $self->version($version) if defined $version;

    if (defined $headers) {
        croak 'headers must be an array reference of field-name/value pairs'
            unless ref($headers) eq 'ARRAY';

        for my $field (@$headers) {
            croak 'each header must be a two-element array reference'
                unless ref($field) eq 'ARRAY' && @$field == 2;
            $self->add_header($field->[0], $field->[1]);
        }
    }

    if (defined $trailers) {
        croak 'trailers must be an array reference of field-name/value pairs'
            unless ref($trailers) eq 'ARRAY';

        for my $field (@$trailers) {
            croak 'each trailer must be a two-element array reference'
                unless ref($field) eq 'ARRAY' && @$field == 2;
            $self->add_trailer($field->[0], $field->[1]);
        }
    }

    $self->body($body) if $has_body;

    return $self;
}

sub _byte_string {
    my ($name, $value) = @_;

    croak "$name must be a defined plain scalar"
        unless defined($value) && !ref($value);

    my $copy = "$value";
    croak "$name must be a byte string"
        unless utf8::downgrade($copy, 1);

    return $copy;
}

sub _header_name {
    my ($value) = @_;
    my $name = _byte_string('header name', $value);

    croak 'header name must be an HTTP token'
        unless $name =~ /\A[!\#\$%&'*+\-.\^_\x60|~0-9A-Za-z]+\z/;

    return $name;
}

sub _header_value {
    my ($value) = @_;
    my $field_value = _byte_string('header value', $value);

    croak 'header value contains a prohibited control byte'
        if $field_value =~ /[\x00-\x08\x0a-\x1f\x7f]/;

    return $field_value;
}

sub _header_index {
    my ($value) = @_;

    croak 'header index must be a non-negative integer'
        unless defined($value)
            && !ref($value)
            && $value =~ /\A[0-9]+\z/;

    return 0 + $value;
}

sub _ascii_lc {
    my ($value) = @_;
    $value =~ tr/A-Z/a-z/;
    return $value;
}

sub _assert_mutable {
    my ($self) = @_;
    croak 'message is immutable' if $self->{committed};
    return;
}

sub version {
    my ($self, @args) = @_;
    return $self->{version} unless @args;

    croak 'version() accepts at most one value' unless @args == 1;
    $self->_assert_mutable;

    if (!defined $args[0]) {
        $self->{version} = undef;
        return $self;
    }

    my $version = _byte_string('version', $args[0]);
    croak 'version must contain digits with an optional decimal part'
        unless $version =~ /\A[0-9]+(?:\.[0-9]+)?\z/;

    $self->{version} = $version;
    return $self;
}

sub header {
    my ($self, @args) = @_;

    croak 'header() requires a field name' unless @args;
    croak 'header() accepts a field name and optional value' unless @args <= 2;

    my $name = _header_name($args[0]);
    my $key = _ascii_lc($name);

    if (@args == 1) {
        for my $field (@{ $self->{headers} }) {
            return $field->[1] if _ascii_lc($field->[0]) eq $key;
        }
        return;
    }

    $self->_assert_mutable;
    my $value = _header_value($args[1]);
    my @headers;
    my $inserted;

    for my $field (@{ $self->{headers} }) {
        if (_ascii_lc($field->[0]) eq $key) {
            if (!$inserted) {
                push @headers, [ $name, $value ];
                $inserted = 1;
            }
            next;
        }

        push @headers, [ @$field ];
    }

    push @headers, [ $name, $value ] unless $inserted;
    $self->{headers} = \@headers;

    return $self;
}

sub header_values {
    my ($self, @args) = @_;

    croak 'header_values() requires exactly one field name' unless @args == 1;

    my $key = _ascii_lc(_header_name($args[0]));

    return [
        map { $_->[1] }
        grep { _ascii_lc($_->[0]) eq $key }
        @{ $self->{headers} }
    ];
}

sub add_header {
    my ($self, @args) = @_;

    croak 'add_header() requires exactly a field name and value'
        unless @args == 2;

    $self->_assert_mutable;

    push @{ $self->{headers} }, [
        _header_name($args[0]),
        _header_value($args[1]),
    ];

    return $self;
}

sub remove_header {
    my ($self, @args) = @_;

    croak 'remove_header() requires exactly one field name' unless @args == 1;

    $self->_assert_mutable;
    my $key = _ascii_lc(_header_name($args[0]));

    $self->{headers} = [
        map { [ @$_ ] }
        grep { _ascii_lc($_->[0]) ne $key }
        @{ $self->{headers} }
    ];

    return $self;
}

sub header_count {
    my ($self, @args) = @_;
    croak 'header_count() does not accept arguments' if @args;
    return scalar @{ $self->{headers} };
}

sub header_name {
    my ($self, @args) = @_;

    croak 'header_name() requires exactly one index' unless @args == 1;

    my $index = _header_index($args[0]);
    return if $index >= @{ $self->{headers} };

    return $self->{headers}[$index][0];
}

sub header_value {
    my ($self, @args) = @_;

    croak 'header_value() requires exactly one index' unless @args == 1;

    my $index = _header_index($args[0]);
    return if $index >= @{ $self->{headers} };

    return $self->{headers}[$index][1];
}

sub trailer {
    my ($self, @args) = @_;

    croak 'trailer() requires a field name' unless @args;
    croak 'trailer() accepts a field name and optional value' unless @args <= 2;

    my $name = _header_name($args[0]);
    my $key = _ascii_lc($name);

    if (@args == 1) {
        for my $field (@{ $self->{trailers} }) {
            return $field->[1] if _ascii_lc($field->[0]) eq $key;
        }
        return;
    }

    $self->_assert_mutable;
    my $value = _header_value($args[1]);
    my @trailers;
    my $inserted;

    for my $field (@{ $self->{trailers} }) {
        if (_ascii_lc($field->[0]) eq $key) {
            if (!$inserted) {
                push @trailers, [ $name, $value ];
                $inserted = 1;
            }
            next;
        }

        push @trailers, [ @$field ];
    }

    push @trailers, [ $name, $value ] unless $inserted;
    $self->{trailers} = \@trailers;

    return $self;
}

sub trailer_values {
    my ($self, @args) = @_;

    croak 'trailer_values() requires exactly one field name' unless @args == 1;

    my $key = _ascii_lc(_header_name($args[0]));

    return [
        map { $_->[1] }
        grep { _ascii_lc($_->[0]) eq $key }
        @{ $self->{trailers} }
    ];
}

sub add_trailer {
    my ($self, @args) = @_;

    croak 'add_trailer() requires exactly a field name and value'
        unless @args == 2;

    $self->_assert_mutable;

    push @{ $self->{trailers} }, [
        _header_name($args[0]),
        _header_value($args[1]),
    ];

    return $self;
}

sub remove_trailer {
    my ($self, @args) = @_;

    croak 'remove_trailer() requires exactly one field name' unless @args == 1;

    $self->_assert_mutable;
    my $key = _ascii_lc(_header_name($args[0]));

    $self->{trailers} = [
        map { [ @$_ ] }
        grep { _ascii_lc($_->[0]) ne $key }
        @{ $self->{trailers} }
    ];

    return $self;
}

sub trailer_count {
    my ($self, @args) = @_;
    croak 'trailer_count() does not accept arguments' if @args;
    return scalar @{ $self->{trailers} };
}

sub trailer_name {
    my ($self, @args) = @_;

    croak 'trailer_name() requires exactly one index' unless @args == 1;

    my $index = _header_index($args[0]);
    return if $index >= @{ $self->{trailers} };

    return $self->{trailers}[$index][0];
}

sub trailer_value {
    my ($self, @args) = @_;

    croak 'trailer_value() requires exactly one index' unless @args == 1;

    my $index = _header_index($args[0]);
    return if $index >= @{ $self->{trailers} };

    return $self->{trailers}[$index][1];
}

sub has_trailers {
    my ($self, @args) = @_;
    croak 'has_trailers() does not accept arguments' if @args;
    return @{ $self->{trailers} } ? 1 : 0;
}

sub _append_received_trailer {
    my ($self, $name, $value) = @_;

    push @{ $self->{trailers} }, [
        _header_name($name),
        _header_value($value),
    ];

    return $self;
}

sub body {
    my ($self, @args) = @_;
    return $self->{body} unless @args;

    croak 'body() accepts at most one value' unless @args == 1;

    $self->_assert_mutable;
    croak 'body() cannot replace an incremental body'
        if $self->{incremental_body};
    $self->{body} = _byte_string('body', $args[0]);
    $self->{has_buffered_body} = 1;

    return $self;
}

sub _begin_stream_body {
    my ($self) = @_;

    $self->_assert_mutable;

    croak 'message already has a complete scalar body'
        if $self->{has_buffered_body};
    croak 'message already has an incremental body producer'
        if $self->{incremental_body};

    $self->{incremental_body} = 1;
    $self->{complete} = 0;

    return $self;
}

sub _has_incremental_body {
    my ($self) = @_;
    return $self->{incremental_body} ? 1 : 0;
}

sub _has_scalar_body {
    my ($self) = @_;
    return $self->{has_buffered_body} ? 1 : 0;
}

sub has_buffered_body {
    my ($self, @args) = @_;
    croak 'has_buffered_body() does not accept arguments' if @args;
    return $self->{has_buffered_body} ? 1 : 0;
}

sub is_complete {
    my ($self, @args) = @_;
    croak 'is_complete() does not accept arguments' if @args;
    return $self->{complete} ? 1 : 0;
}

sub is_mutable {
    my ($self, @args) = @_;
    croak 'is_mutable() does not accept arguments' if @args;
    return $self->{committed} ? 0 : 1;
}

sub headers_are_lossless {
    my ($self, @args) = @_;
    croak 'headers_are_lossless() does not accept arguments' if @args;
    return 1;
}

sub reset_code {
    my ($self, @args) = @_;
    croak 'reset_code() does not accept arguments' if @args;
    return $self->{reset_code};
}

sub stop_sending_code {
    my ($self, @args) = @_;
    croak 'stop_sending_code() does not accept arguments' if @args;
    return $self->{stop_sending_code};
}

sub is_aborted {
    my ($self, @args) = @_;
    croak 'is_aborted() does not accept arguments' if @args;
    return defined($self->{reset_code}) || defined($self->{stop_sending_code})
        ? 1
        : 0;
}

sub _mark_reset {
    my ($self, $code) = @_;
    $self->{reset_code} = 0 + $code;
    $self->{complete} = 0;
    return $self;
}

sub _mark_stop_sending {
    my ($self, $code) = @_;
    $self->{stop_sending_code} = 0 + $code;
    $self->{complete} = 0;
    return $self;
}

sub _append_received_body {
    my ($self, $bytes) = @_;

    $bytes = _byte_string('received body', $bytes);

    if (!$self->{has_buffered_body}) {
        $self->{body} = '';
        $self->{has_buffered_body} = 1;
    }

    $self->{body} .= $bytes;
    return $self;
}

sub _commit {
    my ($self) = @_;
    $self->{committed} = 1;
    return $self;
}

sub _mark_incomplete {
    my ($self) = @_;
    $self->{complete} = 0;
    return $self;
}

sub _mark_complete {
    my ($self) = @_;
    $self->{complete} = 1;
    return $self;
}

1;