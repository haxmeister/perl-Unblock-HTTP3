use strict;
use warnings;

use FindBin ();
use IO::Select;
use IO::Socket::INET;
use Time::HiRes qw(time);

use Net::QUIC;
use Net::QUIC::Driver;
use Unblock::HTTP3;
use Unblock::HTTP3::Client;
use Unblock::HTTP3::Connection;
use Unblock::HTTP3::Server;
use Uniform::HTTP::Request;

my $requests = $ENV{UNBLOCK_HTTP3_BENCH_REQUESTS} // 1000;
my $warmup = $ENV{UNBLOCK_HTTP3_BENCH_WARMUP} // 100;
my $body_bytes = $ENV{UNBLOCK_HTTP3_BENCH_BODY_BYTES} // 1024;
my $concurrency_text = $ENV{UNBLOCK_HTTP3_BENCH_CONCURRENCY} // '1,16,64';

for my $pair (
    [ requests => $requests ],
    [ warmup => $warmup ],
    [ body_bytes => $body_bytes ],
) {
    my ($name, $value) = @$pair;
    die "$name must be a non-negative integer\n"
        unless defined($value) && $value =~ /\A\d+\z/;
}

die "requests must be greater than zero\n" unless $requests > 0;
die "body_bytes must be greater than zero\n" unless $body_bytes > 0;

my @concurrency = split /,/, $concurrency_text;
die "at least one concurrency value is required\n" unless @concurrency;

for my $value (@concurrency) {
    die "concurrency values must be positive integers\n"
        unless defined($value) && $value =~ /\A\d+\z/ && $value > 0;
}

my $cert_file = "$FindBin::Bin/../t/fixtures/localhost-cert.pem";
my $key_file = "$FindBin::Bin/../t/fixtures/localhost-key.pem";

-f $cert_file or die "missing bundled loopback TLS certificate: $cert_file\n";
-f $key_file or die "missing bundled loopback TLS private key: $key_file\n";

sub make_udp_socket {
    my $socket = IO::Socket::INET->new(
        LocalAddr => '127.0.0.1',
        LocalPort => 0,
        Proto     => 'udp',
    );

    die "could not create loopback UDP socket: $!\n"
        unless defined $socket;

    return $socket;
}

sub send_datagram {
    my ($socket, $datagram) = @_;

    my $bytes = $datagram->data;
    my $sent = send(
        $socket,
        $bytes,
        0,
        $datagram->peer,
    );

    die "loopback UDP send failed: $!\n"
        unless defined $sent;
    die "loopback UDP send was partial\n"
        if $sent != length($bytes);

    return 1;
}

sub make_context {
    my $server_socket = make_udp_socket();
    my $client_socket = make_udp_socket();

    my $server_local = getsockname($server_socket);
    my $client_local = getsockname($client_socket);

    my ($server_deadline, $client_deadline);

    my $server_driver = Net::QUIC::Driver->server(
        alpn             => 'h3',
        certificate_file => $cert_file,
        private_key_file => $key_file,

        send => sub {
            my ($datagram) = @_;
            return send_datagram($server_socket, $datagram);
        },

        set_timeout => sub {
            my ($after) = @_;
            $server_deadline = defined($after)
                ? time() + $after
                : undef;
            return;
        },
    );

    my $client_driver = Net::QUIC::Driver->client(
        local       => $client_local,
        peer        => $server_local,
        alpn        => 'h3',
        server_name => 'localhost',
        ca_file     => $cert_file,

        send => sub {
            my ($datagram) = @_;
            return send_datagram($client_socket, $datagram);
        },

        set_timeout => sub {
            my ($after) = @_;
            $client_deadline = defined($after)
                ? time() + $after
                : undef;
            return;
        },
    );

    my $selector = IO::Select->new($client_socket, $server_socket);

    my $service_once = sub {
        my ($hard_deadline) = @_;

        my $now = time();

        if (defined($server_deadline) && $server_deadline <= $now) {
            $server_deadline = undef;
            $server_driver->timeout;
        }

        $now = time();

        if (defined($client_deadline) && $client_deadline <= $now) {
            $client_deadline = undef;
            $client_driver->timeout;
        }

        $now = time();

        my $wait = 0.01;

        for my $deadline ($server_deadline, $client_deadline, $hard_deadline) {
            next unless defined $deadline;

            my $remaining = $deadline - $now;
            $remaining = 0 if $remaining < 0;
            $wait = $remaining if $remaining < $wait;
        }

        for my $socket ($selector->can_read($wait)) {
            my $bytes = '';
            my $peer = recv($socket, $bytes, 65535, 0);

            die "loopback UDP receive failed: $!\n"
                unless defined $peer;

            my $local = getsockname($socket);
            die "could not read loopback UDP local address: $!\n"
                unless defined $local;

            if (fileno($socket) == fileno($server_socket)) {
                $server_driver->receive($bytes, $local, $peer);
            } else {
                $client_driver->receive($bytes, $local, $peer);
            }
        }

        return;
    };

    my $run_until = sub {
        my ($condition, $seconds) = @_;
        my $hard_deadline = time() + $seconds;

        while (time() < $hard_deadline) {
            return 1 if $condition->();
            $service_once->($hard_deadline);
        }

        return $condition->() ? 1 : 0;
    };

    $server_driver->start;
    $client_driver->start;

    my $client_quic = $client_driver->connection;
    my $server_quic;

    die "QUIC/TLS handshake timed out\n"
        unless $run_until->(
            sub {
                $server_quic ||= $server_driver->next_connection;

                return $server_quic
                    && $server_quic->ready
                    && $client_quic->ready;
            },
            10,
        );

    my $client_h3 = Unblock::HTTP3::Client->new(
        quic => $client_quic,
    );

    my $server_h3 = Unblock::HTTP3::Server->new(
        quic => $server_quic,
    );

    $client_h3->start;
    $server_h3->start;

    die "HTTP/3 SETTINGS exchange timed out\n"
        unless $run_until->(
            sub {
                return $client_h3->peer_settings_received
                    && $server_h3->peer_settings_received;
            },
            10,
        );

    return {
        client_socket => $client_socket,
        server_socket => $server_socket,
        client_quic   => $client_quic,
        server_quic   => $server_quic,
        client_h3     => $client_h3,
        server_h3     => $server_h3,
        service_once  => $service_once,
    };
}

sub run_requests {
    my ($ctx, $count, $concurrency, $response_body) = @_;

    return 0 if $count == 0;

    my $client_h3 = $ctx->{client_h3};
    my $server_h3 = $ctx->{server_h3};
    my $service_once = $ctx->{service_once};

    my $issued = 0;
    my $completed = 0;
    my $credit_stalls = 0;
    my $peak_active = 0;
    my $first_stall_active;
    my @active;

    my $hard_deadline = time() + 120;
    my $start = time();

    while ($completed < $count) {
        die "benchmark request batch timed out\n"
            if time() >= $hard_deadline;

        while ($issued < $count && @active < $concurrency) {
            my $next_id = $issued + 1;

            my $request = Uniform::HTTP::Request->new(
                method    => 'GET',
                target    => "/bench/$next_id",
                scheme    => 'https',
                authority => 'localhost',
            );

            my $tx = $client_h3->request($request);

            if (!defined $tx) {
                ++$credit_stalls;
                $first_stall_active = scalar(@active)
                    unless defined $first_stall_active;
                last;
            }

            ++$issued;
            push @active, $tx;
            $peak_active = @active if @active > $peak_active;
        }

        $service_once->($hard_deadline);

        while (my $tx = $server_h3->next_transaction) {
            my $response = $tx->response;

            $response->status(200);
            $response->header('content-type', 'application/octet-stream');
            $response->body($response_body);

            $tx->respond($tx->response);
        }

        my @remaining;

        for my $tx (@active) {
            if ($tx->is_terminal) {
                my $response = $tx->response;

                die "client Transaction completed without response\n"
                    unless defined $response;
                die "unexpected HTTP status " . $response->status . "\n"
                    unless $response->status == 200;

                ++$completed;
            } else {
                push @remaining, $tx;
            }
        }

        @active = @remaining;

        die "client HTTP/3 connection failed: " . ($client_h3->error // 'unknown') . "\n"
            if $client_h3->failed;
        die "server HTTP/3 connection failed: " . ($server_h3->error // 'unknown') . "\n"
            if $server_h3->failed;
    }

    return {
        elapsed            => time() - $start,
        credit_stalls      => $credit_stalls,
        peak_active        => $peak_active,
        first_stall_active => $first_stall_active,
    };
}

sub close_context {
    my ($ctx) = @_;

    eval { $ctx->{client_quic}->close };
    eval { $ctx->{server_quic}->close };

    close $ctx->{client_socket};
    close $ctx->{server_socket};

    return;
}

print "Unblock::HTTP3 loopback benchmark\n";
print "perl=$]\n";
print "unblock_http3=$Unblock::HTTP3::VERSION\n";
print "net_quic=$Net::QUIC::VERSION\n";
print "requests_per_case=$requests\n";
print "warmup_requests=$warmup\n";
print "response_body_bytes=$body_bytes\n";
print "\n";
printf "%-12s %-12s %-12s %-16s %-18s %-14s %-12s %-12s\n",
    'concurrency',
    'requests',
    'seconds',
    'requests/sec',
    'payload MiB/sec',
    'credit stalls',
    'peak active',
    'first stall';

my $response_body = 'x' x $body_bytes;

for my $concurrency (@concurrency) {
    my $ctx = make_context();

    run_requests(
        $ctx,
        $warmup,
        $concurrency,
        $response_body,
    ) if $warmup;

    my $result = run_requests(
        $ctx,
        $requests,
        $concurrency,
        $response_body,
    );

    my $elapsed = $result->{elapsed};
    my $requests_per_second = $requests / $elapsed;
    my $mib_per_second =
        ($requests * $body_bytes) / (1024 * 1024) / $elapsed;

    printf "%-12d %-12d %-12.6f %-16.2f %-18.2f %-14d %-12d %-12s\n",
        $concurrency,
        $requests,
        $elapsed,
        $requests_per_second,
        $mib_per_second,
        $result->{credit_stalls},
        $result->{peak_active},
        defined($result->{first_stall_active})
            ? $result->{first_stall_active}
            : '-';

    close_context($ctx);
}
