use strict;
use warnings;

use IO::Select;
use IO::Socket::INET;
use Socket qw(inet_aton pack_sockaddr_in);
use Test2::V0;
use Time::HiRes qw(time);

use Net::QUIC::Driver;
use Unblock::HTTP3::Connection;
use Uniform::HTTP::Request;

plan skip_all => 'set UNBLOCK_HTTP3_PUBLIC_INTEROP=1 to run public HTTP/3 interoperability tests'
    unless $ENV{UNBLOCK_HTTP3_PUBLIC_INTEROP};

my @target = (
    {
        name => 'Cloudflare',
        host => 'www.cloudflare.com',
        port => 443,
    },
    {
        name => 'Google',
        host => 'www.google.com',
        port => 443,
    },
    {
        name => 'LiteSpeed',
        host => 'http3-test.litespeedtech.com',
        port => 4433,
    },
);

if (defined($ENV{UNBLOCK_HTTP3_INTEROP_TARGETS})
    && length($ENV{UNBLOCK_HTTP3_INTEROP_TARGETS})) {
    @target = ();

    for my $entry (split /,/, $ENV{UNBLOCK_HTTP3_INTEROP_TARGETS}) {
        my ($host, $port) = split /:/, $entry, 2;
        $port = 443 unless defined($port) && length($port);

        push @target, {
            name => $host,
            host => $host,
            port => 0 + $port,
        };
    }
}

sub run_target {
    my ($target) = @_;

    my $host = $target->{host};
    my $port = $target->{port};
    my $address = inet_aton($host);

    ok(defined($address), "DNS resolves $host")
        or return;

    my $peer = pack_sockaddr_in($port, $address);

    my $socket = IO::Socket::INET->new(
        LocalAddr => '0.0.0.0',
        LocalPort => 0,
        Proto     => 'udp',
    );

    ok(defined($socket), 'creates UDP socket')
        or return;

    my $local = getsockname($socket);
    my $deadline;

    my $driver = Net::QUIC::Driver->client(
        local       => $local,
        peer        => $peer,
        alpn        => 'h3',
        server_name => $host,

        send => sub {
            my ($datagram) = @_;
            my $bytes = $datagram->data;
            my $sent = send(
                $socket,
                $bytes,
                0,
                $datagram->peer,
            );

            die "UDP send failed: $!"
                unless defined $sent;
            die "partial UDP send"
                if $sent != length($bytes);

            return 1;
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

    my $selector = IO::Select->new($socket);

    my $service_once = sub {
        my ($hard_deadline) = @_;

        if (defined($deadline) && $deadline <= time()) {
            $deadline = undef;
            $driver->timeout;
        }

        my $now = time();
        my $wait = 0.05;

        for my $candidate ($deadline, $hard_deadline) {
            next unless defined $candidate;
            my $remaining = $candidate - $now;
            $remaining = 0 if $remaining < 0;
            $wait = $remaining if $remaining < $wait;
        }

        for my $ready ($selector->can_read($wait)) {
            my $bytes = '';
            my $remote = recv($ready, $bytes, 65535, 0);

            die "UDP receive failed: $!"
                unless defined $remote;

            $driver->receive(
                $bytes,
                getsockname($ready),
                $remote,
            );
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

    my $quic = $driver->connection;

    ok(
        $run_until->(sub { $quic->ready }, 15),
        'QUIC/TLS handshake completes with h3 ALPN',
    ) or return;

    my $h3 = Unblock::HTTP3::Connection->client(
        quic         => $quic,
        receive_body => 'stream',
    );
    $h3->start;

    my @path = ('/', '/robots.txt');
    my @tx;
    my %body_bytes;

    for my $path (@path) {
        my $authority = $port == 443
            ? $host
            : "$host:$port";

        my $request = Uniform::HTTP::Request->new(
            method    => 'GET',
            target    => $path,
            scheme    => 'https',
            authority => $authority,
        );

        my $tx = $h3->request(
            $request,
            receive_body => {
                on_data => sub {
                    my ($reader, $chunk) = @_;
                    $body_bytes{$path} += length($chunk);
                    return;
                },
            },
        );

        ok(defined($tx), "submits GET $path")
            or return;

        push @tx, $tx;
    }

    ok(
        $run_until->(
            sub {
                return 0 if $h3->failed;
                for my $tx (@tx) {
                    return 0 unless $tx->is_terminal;
                }
                return 1;
            },
            20,
        ),
        'both multiplexed HTTP/3 requests reach terminal state',
    ) or do {
        diag('HTTP/3 error: ' . ($h3->error // 'none'));
        return;
    };

    ok(!$h3->failed, 'HTTP/3 connection remains healthy');

    for my $i (0 .. $#tx) {
        my $response = $tx[$i]->response;
        ok(defined($response), "GET $path[$i] receives response headers")
            or next;

        my $status = $response->status;
        cmp_ok($status, '>=', 200, "GET $path[$i] status is final");
        cmp_ok($status, '<', 500, "GET $path[$i] is accepted by public server");

        my $server = $response->header('server');
        diag(
            "$target->{name} $host:$port $path[$i] -> "
            . "$status; server="
            . (defined($server) ? $server : '(not sent)')
            . "; streamed_body_bytes="
            . ($body_bytes{$path[$i]} // 0)
        );
    }

    $quic->close;
}

for my $target (@target) {
    subtest "$target->{name} HTTP/3 server" => sub {
        run_target($target);
    };
}

done_testing;
