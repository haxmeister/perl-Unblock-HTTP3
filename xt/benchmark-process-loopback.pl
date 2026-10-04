use strict;
use warnings;

use FindBin ();
use IO::Select;
use IO::Socket::INET;
use POSIX qw(WNOHANG);
use Time::HiRes qw(time);

use Net::QUIC;
use Net::QUIC::Driver;
use Unblock::HTTP3;
use Unblock::HTTP3::Connection;
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

sub run_server {
    my ($port_writer, $response_body) = @_;

    $SIG{TERM} = sub { exit 0 };

    my $socket = make_udp_socket();
    my $deadline;

    my $driver = Net::QUIC::Driver->server(
        alpn             => 'h3',
        certificate_file => $cert_file,
        private_key_file => $key_file,

        send => sub {
            my ($datagram) = @_;
            return send_datagram($socket, $datagram);
        },

        set_timeout => sub {
            my ($after) = @_;
            $deadline = defined($after)
                ? time() + $after
                : undef;
            return;
        },
    );

    $driver->start;

    my $old = select($port_writer);
    $| = 1;
    select($old);

    print {$port_writer} $socket->sockport, "\n"
        or die "could not publish server port: $!\n";
    close $port_writer;

    my $selector = IO::Select->new($socket);
    my $server_quic;
    my $h3;

    while (1) {
        my $now = time();

        if (defined($deadline) && $deadline <= $now) {
            $deadline = undef;
            $driver->timeout;
        }

        $now = time();
        my $wait = 0.01;

        if (defined $deadline) {
            my $remaining = $deadline - $now;
            $remaining = 0 if $remaining < 0;
            $wait = $remaining if $remaining < $wait;
        }

        for my $ready ($selector->can_read($wait)) {
            my $bytes = '';
            my $peer = recv($ready, $bytes, 65535, 0);

            die "server UDP receive failed: $!\n"
                unless defined $peer;

            my $local = getsockname($ready);
            die "could not read server UDP local address: $!\n"
                unless defined $local;

            $driver->receive($bytes, $local, $peer);
        }

        $server_quic ||= $driver->next_connection;

        if ($server_quic && $server_quic->ready && !$h3) {
            $h3 = Unblock::HTTP3::Connection->server(
                quic => $server_quic,
            );
            $h3->start;
        }

        if ($h3) {
            while (my $tx = $h3->next_transaction) {
                my $response = $tx->response;

                $response->status(200);
                $response->header(
                    'content-type',
                    'application/octet-stream',
                );
                $response->body($response_body);

                $tx->send_response;
            }

            die "server HTTP/3 connection failed: "
                . ($h3->error // 'unknown')
                . "\n"
                if $h3->failed;
        }
    }
}

sub start_server_process {
    my ($response_body) = @_;

    pipe my $port_reader, my $port_writer
        or die "could not create server-port pipe: $!\n";

    my $pid = fork();
    die "fork failed: $!\n" unless defined $pid;

    if ($pid == 0) {
        close $port_reader;

        eval {
            run_server($port_writer, $response_body);
            1;
        } or do {
            my $error = $@ || 'unknown server error';
            print STDERR $error;
            exit 1;
        };

        exit 0;
    }

    close $port_writer;

    my $port = <$port_reader>;
    close $port_reader;

    if (!defined $port) {
        waitpid($pid, 0);
        die "server process exited before publishing its UDP port\n";
    }

    chomp $port;

    die "server process published invalid UDP port '$port'\n"
        unless $port =~ /\A\d+\z/ && $port > 0 && $port <= 65535;

    return ($pid, 0 + $port);
}

sub make_client_context {
    my ($server_pid, $server_port) = @_;

    my $socket = IO::Socket::INET->new(
        PeerAddr => '127.0.0.1',
        PeerPort => $server_port,
        Proto     => 'udp',
    );

    die "could not create client UDP socket: $!\n"
        unless defined $socket;

    my $local = getsockname($socket);
    my $peer = getpeername($socket);

    die "could not read client UDP local address: $!\n"
        unless defined $local;
    die "could not read client UDP peer address: $!\n"
        unless defined $peer;

    my $deadline;
    my $child_status;

    my $driver = Net::QUIC::Driver->client(
        local       => $local,
        peer        => $peer,
        alpn        => 'h3',
        server_name => 'localhost',
        ca_file     => $cert_file,

        send => sub {
            my ($datagram) = @_;
            return send_datagram($socket, $datagram);
        },

        set_timeout => sub {
            my ($after) = @_;
            $deadline = defined($after)
                ? time() + $after
                : undef;
            return;
        },
    );

    my $selector = IO::Select->new($socket);

    my $check_server = sub {
        return if defined $child_status;

        my $waited = waitpid($server_pid, WNOHANG);

        if ($waited == $server_pid) {
            $child_status = $?;
            die "server process exited during benchmark with status "
                . ($child_status >> 8)
                . "\n";
        }

        return;
    };

    my $service_once = sub {
        my ($hard_deadline) = @_;

        $check_server->();

        my $now = time();

        if (defined($deadline) && $deadline <= $now) {
            $deadline = undef;
            $driver->timeout;
        }

        $now = time();
        my $wait = 0.01;

        for my $candidate ($deadline, $hard_deadline) {
            next unless defined $candidate;

            my $remaining = $candidate - $now;
            $remaining = 0 if $remaining < 0;
            $wait = $remaining if $remaining < $wait;
        }

        for my $ready ($selector->can_read($wait)) {
            my $bytes = '';
            my $remote = recv($ready, $bytes, 65535, 0);

            die "client UDP receive failed: $!\n"
                unless defined $remote;

            my $socket_local = getsockname($ready);
            die "could not read client UDP local address: $!\n"
                unless defined $socket_local;

            $driver->receive(
                $bytes,
                $socket_local,
                $remote,
            );
        }

        $check_server->();

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

    $driver->start;

    my $quic = $driver->connection;

    die "QUIC/TLS handshake timed out\n"
        unless $run_until->(
            sub { $quic->ready },
            10,
        );

    my $h3 = Unblock::HTTP3::Connection->client(
        quic => $quic,
    );

    $h3->start;

    die "HTTP/3 SETTINGS exchange timed out\n"
        unless $run_until->(
            sub { $h3->peer_settings_received },
            10,
        );

    return {
        socket       => $socket,
        quic         => $quic,
        h3           => $h3,
        service_once => $service_once,
    };
}

sub run_requests {
    my ($ctx, $count, $concurrency) = @_;

    return {
        elapsed            => 0,
        credit_stalls      => 0,
        peak_active        => 0,
        first_stall_active => undef,
    } if $count == 0;

    my $h3 = $ctx->{h3};
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

            my $tx = $h3->request($request);

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

        die "client HTTP/3 connection failed: "
            . ($h3->error // 'unknown')
            . "\n"
            if $h3->failed;
    }

    return {
        elapsed            => time() - $start,
        credit_stalls      => $credit_stalls,
        peak_active        => $peak_active,
        first_stall_active => $first_stall_active,
    };
}

sub stop_context {
    my ($ctx, $server_pid) = @_;

    eval { $ctx->{quic}->close };
    close $ctx->{socket};

    kill 'TERM', $server_pid;
    waitpid($server_pid, 0);

    my $status = $?;

    die "server process failed with status " . ($status >> 8) . "\n"
        if $status != 0;

    return;
}

print "Unblock::HTTP3 split-process loopback benchmark\n";
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
    my ($server_pid, $server_port) =
        start_server_process($response_body);

    my $ctx = make_client_context(
        $server_pid,
        $server_port,
    );

    run_requests(
        $ctx,
        $warmup,
        $concurrency,
    ) if $warmup;

    my $result = run_requests(
        $ctx,
        $requests,
        $concurrency,
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

    stop_context($ctx, $server_pid);
}
