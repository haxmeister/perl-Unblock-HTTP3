use strict;
use warnings;

use Time::HiRes qw(time);

use Uniform::HTTP::Request;
use Unblock::HTTP3;
use Unblock::HTTP3::Connection;
use Unblock::HTTP3::_Native;

my $iterations = $ENV{UNBLOCK_HTTP3_MICRO_ITERATIONS} // 20_000;
my $native_iterations =
    $ENV{UNBLOCK_HTTP3_MICRO_NATIVE_ITERATIONS} // 10_000;

for my $pair (
    [ iterations => $iterations ],
    [ native_iterations => $native_iterations ],
) {
    my ($name, $value) = @$pair;

    die "$name must be a positive integer\n"
        unless defined($value)
            && $value =~ /\A\d+\z/
            && $value > 0;
}

sub measure {
    my ($name, $count, $code) = @_;

    my $start = time();

    for (1 .. $count) {
        $code->();
    }

    my $elapsed = time() - $start;
    my $ops = $count / $elapsed;
    my $us = ($elapsed / $count) * 1_000_000;

    printf "%-34s %10d %12.6f %14.2f %12.2f\n",
        $name,
        $count,
        $elapsed,
        $ops,
        $us;

    return {
        elapsed => $elapsed,
        ops     => $ops,
        us      => $us,
    };
}

sub drain_native {
    my ($native) = @_;

    my $bytes = 0;

    while (my $out = $native->next_write) {
        my ($stream_id, $chunk, $fin) = @$out;
        my $length = length($chunk);

        $bytes += $length;

        $native->add_write_offset(
            $stream_id,
            $length,
        );
    }

    return $bytes;
}

my $request = Uniform::HTTP::Request->new(
    method    => 'GET',
    target    => '/benchmark',
    scheme    => 'https',
    authority => 'example.test',
    headers   => [
        [ 'accept',     '*/*' ],
        [ 'user-agent', 'unblock-http3-benchmark' ],
        [ 'x-one',      'one' ],
        [ 'x-two',      'two' ],
    ],
);

my $native_fields = [
    [ ':method',    'GET' ],
    [ ':scheme',    'https' ],
    [ ':authority', 'example.test' ],
    [ ':path',      '/benchmark' ],
    [ 'accept',     '*/*' ],
    [ 'user-agent', 'unblock-http3-benchmark' ],
    [ 'x-one',      'one' ],
    [ 'x-two',      'two' ],
];

my $sink;

sub legacy_wire_headers {
    my ($message, $context) = @_;

    my @headers;

    for my $index (0 .. $message->header_count - 1) {
        my $name = $message->header_name($index);
        my $value = $message->header_value($index);

        $name =~ tr/A-Z/a-z/;

        my %forbidden = map { $_ => 1 } qw(
            connection
            keep-alive
            proxy-connection
            transfer-encoding
            upgrade
        );

        die "legacy validation rejected $name\n"
            if $forbidden{$name};

        if ($name eq 'te') {
            my $normalized = $value;
            $normalized =~ s/\A[ \t]+//;
            $normalized =~ s/[ \t]+\z//;
            die "legacy TE validation rejected value\n"
                unless $context eq 'request'
                    && lc($normalized) eq 'trailers';
        }

        push @headers, [ $name, $value ];
    }

    return \@headers;
}

print "Unblock::HTTP3 HTTP-layer microbenchmark\n";
print "perl=$]\n";
print "unblock_http3=$Unblock::HTTP3::VERSION\n";
print "nghttp3=" . Unblock::HTTP3::_Native::nghttp3_version() . "\n";
print "\n";
printf "%-34s %10s %12s %14s %12s\n",
    'case',
    'iterations',
    'seconds',
    'ops/sec',
    'us/op';

measure(
    'Uniform request construction',
    $iterations,
    sub {
        $sink = Uniform::HTTP::Request->new(
            method    => 'GET',
            target    => '/benchmark',
            scheme    => 'https',
            authority => 'example.test',
            headers   => [
                [ 'accept',     '*/*' ],
                [ 'user-agent', 'unblock-http3-benchmark' ],
                [ 'x-one',      'one' ],
                [ 'x-two',      'two' ],
            ],
        );
    },
);

measure(
    'Header access/lowercase/copy',
    $iterations,
    sub {
        my @headers;

        for my $index (0 .. $request->header_count - 1) {
            my $name = $request->header_name($index);
            my $value = $request->header_value($index);

            $name =~ tr/A-Z/a-z/;
            push @headers, [ $name, $value ];
        }

        $sink = [ @headers ];
    },
);

measure(
    'HTTP/3 header validation',
    $iterations,
    sub {
        Unblock::HTTP3::Connection::_validate_wire_field('request', 'accept', '*/*');
        Unblock::HTTP3::Connection::_validate_wire_field('request', 'user-agent', 'unblock-http3-benchmark');
        Unblock::HTTP3::Connection::_validate_wire_field('request', 'x-one', 'one');
        Unblock::HTTP3::Connection::_validate_wire_field('request', 'x-two', 'two');
    },
);
measure(
    'Legacy wire field preparation',
    $iterations,
    sub {
        $sink = [
            [ ':method',    $request->method ],
            [ ':scheme',    $request->scheme ],
            [ ':authority', $request->authority ],
            [ ':path',      $request->target ],
            @{ legacy_wire_headers($request, 'request') },
        ];
    },
);
measure(
    'HTTP/3 wire field preparation',
    $iterations,
    sub {
        $sink = [
            [ ':method',    $request->method ],
            [ ':scheme',    $request->scheme ],
            [ ':authority', $request->authority ],
            [ ':path',      $request->target ],
            @{
                Unblock::HTTP3::Connection::_wire_headers(
                    $request,
                    'request',
                )
            },
        ];
    },
);

my $prepared_fields = [
    [ ':method',    $request->method ],
    [ ':scheme',    $request->scheme ],
    [ ':authority', $request->authority ],
    [ ':path',      $request->target ],
    @{ Unblock::HTTP3::Connection::_wire_headers($request, 'request') },
];

measure(
    'HTTP/3 field section sizing',
    $iterations,
    sub {
        $sink = Unblock::HTTP3::Connection::_field_section_size($prepared_fields);
    },
);


my $limit_state = {
    peer_max_field_section_size => '65536',
};

measure(
    'HTTP/3 field section limit check',
    $iterations,
    sub {
        $sink = Unblock::HTTP3::Connection::_assert_peer_field_section_size(
            $limit_state,
            $prepared_fields,
            'benchmark',
        );
    },
);
my $native = Unblock::HTTP3::_Native->client(
    65_536,
    0,
    0,
    0,
    0,
);

$native->bind_streams(2, 6, 10);
drain_native($native);

my $stream_id = 0;
my $native_wire_bytes = 0;

measure(
    'Native nghttp3 request submission',
    $native_iterations,
    sub {
        $native->submit_request(
            $stream_id,
            $native_fields,
        );

        $native_wire_bytes += drain_native($native);
        $stream_id += 4;
    },
);

print "\n";
print "native_wire_bytes=$native_wire_bytes\n";
printf "native_wire_bytes_per_request=%.2f\n",
    $native_wire_bytes / $native_iterations;
