use strict;
use warnings;

use Time::HiRes qw(time);

use Unblock::HTTP3;
use Unblock::HTTP3::_Native;
use Unblock::HTTP3::Transaction;
use Unblock::HTTP3::Response;
use Unblock::HTTP3::Body::Reader;

my $target_bytes =
    $ENV{UNBLOCK_HTTP3_RECEIVE_BENCH_BYTES} // (32 * 1024 * 1024);
my $max_iterations =
    $ENV{UNBLOCK_HTTP3_RECEIVE_BENCH_MAX_ITERATIONS} // 50_000;
my $sizes_text =
    $ENV{UNBLOCK_HTTP3_RECEIVE_BENCH_SIZES}
        // '64,1024,16384,65536,262144,1048576';

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
die "at least one receive body size is required\n" unless @sizes;

for my $size (@sizes) {
    die "receive body sizes must be positive integers\n"
        unless defined($size)
            && $size =~ /\A\d+\z/
            && $size > 0;
}

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

    printf "%-30s %10d %10d %12.6f %14.2f %14.2f\n",
        $name,
        $size,
        $iterations,
        $elapsed,
        $mib_per_second,
        $us_per_chunk;

    return;
}

sub measure_buffered_cycle {
    my ($size, $iterations, $body) = @_;

    my $response =
        Unblock::HTTP3::Response->new(status => 200);

    my $transaction = bless {
        response                 => $response,
        response_receive_mode    => 'buffered',
        response_buffered_body   => [],
        response_buffered_bytes  => 0,
        response_buffered_seen   => 0,
    }, 'Unblock::HTTP3::Transaction';

    my $start = time();

    for (1 .. $iterations) {
        $transaction->_append_buffered_body(
            'response',
            $body,
        );
    }

    $transaction->_finish_received_message('response');

    my $elapsed = time() - $start;
    my $bytes = $size * $iterations;
    my $mib_per_second =
        ($bytes / (1024 * 1024)) / $elapsed;
    my $us_per_chunk =
        ($elapsed / $iterations) * 1_000_000;

    printf "%-30s %10d %10d %12.6f %14.2f %14.2f\n",
        'Buffered multi-chunk finalize',
        $size,
        $iterations,
        $elapsed,
        $mib_per_second,
        $us_per_chunk;

    die "buffered multi-chunk finalization byte count failed\n"
        unless length($response->body // '') == $bytes;

    return;
}

sub measure_slab_cycle {
    my ($size, $iterations, $body, $threshold) = @_;

    my @chunks;
    my $tail = '';
    my $bytes = $size * $iterations;
    my $start = time();

    for (1 .. $iterations) {
        if ($size >= $threshold) {
            push @chunks, $body;
            next;
        }

        $tail .= $body;

        if (length($tail) >= $threshold) {
            push @chunks, $tail;
            $tail = '';
        }
    }

    push @chunks, $tail if length $tail;

    my $joined = @chunks == 1
        ? $chunks[0]
        : join('', @chunks);

    my $elapsed = time() - $start;
    my $mib_per_second =
        ($bytes / (1024 * 1024)) / $elapsed;
    my $us_per_chunk =
        ($elapsed / $iterations) * 1_000_000;

    printf "%-30s %10d %10d %12.6f %14.2f %14.2f\n",
        "Candidate slab ${threshold}B",
        $size,
        $iterations,
        $elapsed,
        $mib_per_second,
        $us_per_chunk;

    die "slab candidate byte count failed\n"
        unless length($joined) == $bytes;

    return;
}

sub transfer_native {
    my ($source, $destination, $timestamp_ref) = @_;

    while (my $out = $source->next_write) {
        my ($stream_id, $bytes, $fin) = @$out;

        my $read = $destination->read_stream(
            $stream_id,
            $bytes,
            $fin ? 1 : 0,
            $$timestamp_ref++,
        );

        die "native peer rejected benchmark setup bytes\n"
            unless @$read == 1;

        $source->add_write_offset(
            $stream_id,
            length($bytes),
        );
    }

    return;
}

sub drain_events {
    my ($native) = @_;

    while ($native->next_event) {
        # Setup events are deliberately excluded from the timed region.
    }

    return;
}

sub prepare_native_data_case {
    my ($body) = @_;

    my $sender = Unblock::HTTP3::_Native->client(
        65_536,
        0,
        0,
        0,
        0,
    );
    my $receiver = Unblock::HTTP3::_Native->server(
        65_536,
        0,
        0,
        0,
        0,
    );

    $sender->bind_streams(2, 6, 10);
    $receiver->bind_streams(3, 7, 11);
    $receiver->set_max_client_streams_bidi(100);

    $sender->submit_request(
        0,
        [
            [ ':method',    'POST' ],
            [ ':scheme',    'https' ],
            [ ':authority', 'example.test' ],
            [ ':path',      '/receive-benchmark' ],
        ],
        undef,
        1,
    );

    my $timestamp = 1;
    transfer_native($sender, $receiver, \$timestamp);
    drain_events($receiver);

    $sender->append_body(0, $body, 0);

    my $wire = '';
    my $stream_offset = 0;

    while (my $out = $sender->next_write) {
        my ($stream_id, $bytes, $fin) = @$out;

        die "unexpected FIN while preparing native DATA benchmark\n"
            if $fin;
        die "unexpected native output stream while preparing DATA benchmark\n"
            if $stream_id != 0;

        $wire .= $bytes;
        $stream_offset += length($bytes);

        $sender->add_write_offset(
            $stream_id,
            length($bytes),
        );
    }

    die "native DATA benchmark produced no wire bytes\n"
        unless length($wire);

    $sender->update_ack_offset(0, $stream_offset);

    return ($receiver, $wire, $timestamp);
}

{
    package Unblock::HTTP3::ReceiveBenchmark::Connection;

    sub new {
        return bless {}, shift;
    }

    sub _consume_received_body {
        return;
    }
}

print "Unblock::HTTP3 incoming-body microbenchmark\n";
print "perl=$]\n";
print "unblock_http3=$Unblock::HTTP3::VERSION\n";
print "nghttp3=" . Unblock::HTTP3::_Native::nghttp3_version() . "\n";
print "target_bytes=$target_bytes\n";
print "\n";
printf "%-30s %10s %10s %12s %14s %14s\n",
    'case',
    'bytes',
    'iterations',
    'seconds',
    'MiB/sec',
    'us/chunk';

for my $size (@sizes) {
    my $iterations = iterations_for_size($size);
    my $body = 'x' x $size;

    my ($native, $wire, $timestamp) =
        prepare_native_data_case($body);

    my $native_sink = 0;

    measure_bytes(
        'Native DATA -> Perl event',
        $size,
        $iterations,
        sub {
            my $result = $native->read_stream(
                0,
                $wire,
                0,
                $timestamp++,
            );

            die "native DATA benchmark parse failed\n"
                unless @$result == 1;

            my $data_events = 0;

            while (my $event = $native->next_event) {
                next unless $event->[0] eq 'data';

                ++$data_events;
                $native_sink += length($event->[2]);
            }

            die "native DATA benchmark did not produce one DATA event\n"
                unless $data_events == 1;
        },
    );

    die "native DATA benchmark payload accounting failed\n"
        unless $native_sink == $size * $iterations;

    my $buffered = bless {
        response_buffered_body  => [],
        response_buffered_bytes => 0,
        response_buffered_seen  => 0,
    }, 'Unblock::HTTP3::Transaction';

    measure_bytes(
        'Buffered accumulation',
        $size,
        $iterations,
        sub {
            $buffered->_append_buffered_body(
                'response',
                $body,
            );
        },
    );

    die "buffered accumulation byte count failed\n"
        unless $buffered->_buffered_body_bytes('response')
            == $size * $iterations;

    measure_buffered_cycle(
        $size,
        $iterations,
        $body,
    );

    measure_slab_cycle(
        $size,
        $iterations,
        $body,
        16_384,
    );

    measure_slab_cycle(
        $size,
        $iterations,
        $body,
        65_536,
    );

    my $bench_connection =
        Unblock::HTTP3::ReceiveBenchmark::Connection->new;

    my $reader_transaction = bless {
        connection => $bench_connection,
        stream_id  => 0,
    }, 'Unblock::HTTP3::Transaction';

    my $reader = Unblock::HTTP3::Body::Reader->_new(
        $reader_transaction,
        'response',
    );

    my $reader_sink = 0;

    measure_bytes(
        'Body::Reader poll delivery',
        $size,
        $iterations,
        sub {
            $reader->_push_owned($body);

            my $chunk = $reader->next_chunk;
            die "Body::Reader benchmark lost a chunk\n"
                unless defined $chunk;

            $reader_sink += length($chunk);
        },
    );

    die "Body::Reader benchmark payload accounting failed\n"
        unless $reader_sink == $size * $iterations;
    die "Body::Reader benchmark retained queued bytes\n"
        unless $reader->pending_bytes == 0;

    my $callback_sink = 0;
    my $callback_reader = Unblock::HTTP3::Body::Reader->_new(
        $reader_transaction,
        'response',
        on_data => sub {
            my ($body_reader, $chunk) = @_;
            $callback_sink += length($chunk);
            return;
        },
    );

    measure_bytes(
        'Body::Reader callback delivery',
        $size,
        $iterations,
        sub {
            $callback_reader->_push_owned($body);
        },
    );

    die "Body::Reader callback payload accounting failed\n"
        unless $callback_sink == $size * $iterations;
    die "Body::Reader callback retained queued bytes\n"
        unless $callback_reader->pending_bytes == 0;

    my $final_sink = 0;

    measure_bytes(
        'Complete buffered response',
        $size,
        $iterations,
        sub {
            my $response =
                Unblock::HTTP3::Response->new(status => 200);

            my $transaction = bless {
                response              => $response,
                response_receive_mode => 'buffered',
                response_buffered_body  => [ $body ],
                response_buffered_bytes => length($body),
                response_buffered_seen  => 1,
            }, 'Unblock::HTTP3::Transaction';

            $transaction->_finish_received_message('response');

            $final_sink += length($response->body // '');
        },
    );

    die "complete buffered response payload accounting failed\n"
        unless $final_sink == $size * $iterations;
}
