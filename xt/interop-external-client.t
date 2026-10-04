use strict;
use warnings;

use File::Temp qw(tempdir);
use FindBin ();
use IO::Select;
use IO::Socket::INET;
use POSIX qw(WNOHANG);
use Test2::V0;
use Time::HiRes qw(time);

use Net::QUIC::Driver;
use Unblock::HTTP3::Connection;

my $client = $ENV{UNBLOCK_HTTP3_EXTERNAL_CLIENT};

plan skip_all => 'set UNBLOCK_HTTP3_EXTERNAL_CLIENT to an independent HTTP/3 client'
    unless defined($client) && length($client);

plan skip_all => "external HTTP/3 client is not executable: $client"
    unless -x $client;

my $cert_file = "$FindBin::Bin/../t/fixtures/localhost-cert.pem";
my $key_file  = "$FindBin::Bin/../t/fixtures/localhost-key.pem";

-f $cert_file or die "missing bundled loopback TLS certificate: $cert_file";
-f $key_file  or die "missing bundled loopback TLS private key: $key_file";

my $socket = IO::Socket::INET->new(
    LocalAddr => '127.0.0.1',
    LocalPort => 0,
    Proto     => 'udp',
);

die "could not create external-client UDP socket: $!"
    unless defined $socket;

my $port = $socket->sockport;
my $deadline;

my $driver = Net::QUIC::Driver->server(
    alpn             => 'h3',
    certificate_file => $cert_file,
    private_key_file => $key_file,

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

my $tmpdir = tempdir(CLEANUP => 1);
my $stdout_file = "$tmpdir/client.stdout";
my $stderr_file = "$tmpdir/client.stderr";
my $url = "https://127.0.0.1:$port/interop";

my $pid = fork();
die "fork failed: $!" unless defined $pid;

if ($pid == 0) {
    close $socket;

    open(STDOUT, '>', $stdout_file)
        or die "could not redirect client stdout: $!";
    open(STDERR, '>', $stderr_file)
        or die "could not redirect client stderr: $!";

    exec { $client } $client, '-insecure', $url;
    die "could not exec external HTTP/3 client: $!";
}

my $selector = IO::Select->new($socket);

my $server_quic;
my $h3;
my $tx;
my $response_sent = 0;
my $child_done = 0;
my $child_status;
my $hard_deadline = time() + 30;

while (time() < $hard_deadline) {
    my $now = time();

    if (defined($deadline) && $deadline <= $now) {
        $deadline = undef;
        $driver->timeout;
    }

    $now = time();

    my $wait = 0.05;

    for my $candidate ($deadline, $hard_deadline) {
        next unless defined $candidate;

        my $remaining = $candidate - $now;
        $remaining = 0 if $remaining < 0;
        $wait = $remaining if $remaining < $wait;
    }

    for my $ready ($selector->can_read($wait)) {
        my $bytes = '';
        my $peer = recv($ready, $bytes, 65535, 0);

        die "UDP receive failed: $!"
            unless defined $peer;

        my $local = getsockname($ready);
        die "could not read UDP local address: $!"
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

    if ($h3 && !$tx) {
        $tx = $h3->next_transaction;

        if ($tx) {
            my $response = $tx->response;

            $response->status(200);
            $response->header('content-type', 'text/plain');
            $response->header('x-unblock-http3-interop', 'quic-go');
            $response->body("unblock-http3-quic-go-interop\n");

            $tx->send_response;
            $response_sent = 1;
        }
    }

    if (!$child_done) {
        my $waited = waitpid($pid, WNOHANG);

        if ($waited == $pid) {
            $child_done = 1;
            $child_status = $?;
        }
    }

    last if $child_done && $response_sent;
}

if (!$child_done) {
    kill 'TERM', $pid;

    my $grace_deadline = time() + 2;
    while (time() < $grace_deadline) {
        my $waited = waitpid($pid, WNOHANG);
        if ($waited == $pid) {
            $child_done = 1;
            $child_status = $?;
            last;
        }
        select undef, undef, undef, 0.05;
    }

    if (!$child_done) {
        kill 'KILL', $pid;
        waitpid($pid, 0);
        $child_done = 1;
        $child_status = $?;
    }
}

sub slurp_file {
    my ($path) = @_;

    return '' unless -f $path;

    open my $fh, '<', $path
        or die "could not read $path: $!";
    local $/;
    my $content = <$fh>;
    close $fh;

    return defined($content) ? $content : '';
}

my $client_output =
    slurp_file($stdout_file)
    . slurp_file($stderr_file);

ok(
    defined($server_quic) && $server_quic->ready,
    'independent client completes QUIC/TLS handshake with h3 ALPN',
);

ok(
    defined($h3) && $h3->started,
    'Unblock::HTTP3 server starts on the independent QUIC connection',
);

ok(
    defined($tx),
    'Unblock::HTTP3 receives an HTTP/3 request from quic-go',
);

if ($tx) {
    my $request = $tx->request;

    is($request->method, 'GET',
        'independent client request preserves GET method');
    is($request->target, '/interop',
        'independent client request preserves path');
    is($request->scheme, 'https',
        'independent client request preserves https scheme');
    like(
        $request->authority,
        qr/^127\.0\.0\.1:\d+$/,
        'independent client request preserves authority',
    );
}

ok($response_sent, 'Unblock::HTTP3 sends a complete HTTP/3 response');
ok($child_done, 'independent HTTP/3 client exits');

if (defined $child_status) {
    is(
        $child_status >> 8,
        0,
        'independent HTTP/3 client reports success',
    );
} else {
    fail('independent HTTP/3 client reports success');
}

like(
    $client_output,
    qr/unblock-http3-quic-go-interop/,
    'independent client receives and consumes the response body',
);

ok(
    !defined($h3) || !$h3->failed,
    'Unblock::HTTP3 server remains healthy after independent-client request',
);

diag($client_output)
    if !$response_sent
        || !defined($child_status)
        || ($child_status >> 8) != 0;

close $socket;

done_testing;
