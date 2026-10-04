use strict;
use warnings;

use Time::HiRes qw(time);

use Unblock::HTTP3;
use Unblock::HTTP3::_Bytes;
use Unblock::HTTP3::_Native;

my $target_bytes =
    $ENV{UNBLOCK_HTTP3_BODY_BENCH_BYTES} // (32 * 1024 * 1024);
my $max_iterations =
    $ENV{UNBLOCK_HTTP3_BODY_BENCH_MAX_ITERATIONS} // 50_000;
my $sizes_text =
    $ENV{UNBLOCK_HTTP3_BODY_BENCH_SIZES} // '64,1024,16384,65536,262144';

for my $pair (
    [ target_bytes => $target_bytes ],
    [ max_iterations => $max_iterations ],
) {
    my ($name, $value) = @$pair;

    die "$name must be a positive integer\n"
        unless defined($value)
            && $value =~ /\A\d+\z/
            && $value > 0;
}

my @sizes = split /,/, $sizes_text;
die "at least one body size is required\n" unless @sizes;

for my $size (@sizes) {
    die "body sizes must be positive integers\n"
        unless defined($size)
            && $size =~ /\A\d+\z/
            && $size > 0;
}

my $fields = [
    [ ':method',    'POST' ],
    [ ':scheme',    'https' ],
    [ ':authority', 'example.test' ],
    [ ':path',      '/body-benchmark' ],
    [ 'content-type', 'application/octet-stream' ],
];

sub iterations_for_size {
    my ($size) = @_;

    my $iterations = int($target_bytes / $size);
    $iterations = 1 if $iterations < 1;
    $iterations = $max_iterations
        if $iterations > $max_iterations;

    return $iterations;
}

sub measure_bytes {
    my ($name, $size, $iterations, $code) = @_;

    my $start = time();

    for (1 .. $iterations) {
        $code->();
    }

    my $elapsed = time() - $start;
    my $bytes = $size * $iterations;
    my $mib_per_second =
        ($bytes / (1024 * 1024)) / $elapsed;
    my $us_per_chunk =
        ($elapsed / $iterations) * 1_000_000;

    printf "%-28s %10d %10d %12.6f %14.2f %14.2f\n",
        $name,
        $size,
        $iterations,
        $elapsed,
        $mib_per_second,
        $us_per_chunk;

    return;
}

sub drain_native {
    my ($native, $offset) = @_;

    while (my $out = $native->next_write) {
        my ($stream_id, $chunk, $fin) = @$out;
        my $length = length($chunk);

        $offset->{$stream_id} += $length;

        $native->add_write_offset(
            $stream_id,
            $length,
        );
    }

    return;
}

print "Unblock::HTTP3 body-copy microbenchmark\n";
print "perl=$]\n";
print "unblock_http3=$Unblock::HTTP3::VERSION\n";
print "nghttp3=" . Unblock::HTTP3::_Native::nghttp3_version() . "\n";
print "target_bytes=$target_bytes\n";
print "\n";
printf "%-28s %10s %10s %12s %14s %14s\n",
    'case',
    'bytes',
    'iterations',
    'seconds',
    'MiB/sec',
    'us/chunk';

for my $size (@sizes) {
    my $iterations = iterations_for_size($size);
    my $body = 'x' x $size;
    my $sink;

    measure_bytes(
        'Perl byte_string',
        $size,
        $iterations,
        sub {
            $sink = Unblock::HTTP3::_Bytes::byte_string(
                'body',
                $body,
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

    my %offset;
    drain_native($native, \%offset);

    $native->submit_request(
        0,
        $fields,
        undef,
        1,
    );

    drain_native($native, \%offset);

    if (defined $offset{0}) {
        $native->update_ack_offset(
            0,
            $offset{0},
        );
    }

    measure_bytes(
        'Native streaming cycle',
        $size,
        $iterations,
        sub {
            $native->append_body(
                0,
                $body,
                0,
            );

            drain_native($native, \%offset);

            $native->update_ack_offset(
                0,
                $offset{0},
            );
        },
    );

    die "streaming retained bytes did not return to zero\n"
        if $native->streaming_retained_bytes != 0;

    $native->append_body(0, '', 1);
    drain_native($native, \%offset);

    if (defined $offset{0}) {
        $native->update_ack_offset(
            0,
            $offset{0},
        );
    }

    $native->close_stream(0);
}
