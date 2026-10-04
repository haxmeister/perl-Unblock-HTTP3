use strict;
use warnings;

use Socket qw(inet_aton pack_sockaddr_in);
use Test2::V0;

use Net::QUIC::Endpoint;
use Unblock::HTTP3::Connection;

my $remembered = {
    1  => '4096',
    6  => '65536',
    7  => '100',
    8  => '1',
    51 => '1',
    84 => '7',
};

my $state = Unblock::HTTP3::Connection::_encode_settings_state($remembered);
ok(defined($state) && length($state) > 5,
    'settings state encodes as opaque bytes');

is(
    Unblock::HTTP3::Connection::_decode_settings_state(
        $state,
        'test state',
    ),
    $remembered,
    'settings state round-trips exactly',
);

like(
    dies {
        Unblock::HTTP3::Connection::_decode_settings_state(
            'bad-state',
            'test state',
        );
    },
    qr/invalid test state/,
    'malformed settings state is rejected',
);

is(
    Unblock::HTTP3::Connection::_settings_compatibility_error(
        $remembered,
        {
            %$remembered,
            1 => '8192',
            6 => '131072',
            7 => '200',
        },
    ),
    undef,
    'larger core limits remain compatible with remembered 0-RTT settings',
);

like(
    Unblock::HTTP3::Connection::_settings_compatibility_error(
        $remembered,
        {
            %$remembered,
            6 => '32768',
        },
    ),
    qr/MAX_FIELD_SECTION_SIZE decreased/,
    'smaller field-section limit is incompatible with 0-RTT',
);

like(
    Unblock::HTTP3::Connection::_settings_compatibility_error(
        $remembered,
        {
            %$remembered,
            51 => '0',
        },
    ),
    qr/setting 51 decreased/,
    'disabling remembered HTTP Datagrams is incompatible with 0-RTT',
);

like(
    Unblock::HTTP3::Connection::_settings_compatibility_error(
        $remembered,
        {
            %$remembered,
            84 => '8',
        },
    ),
    qr/extension setting 84 changed/,
    'generic extension settings require exact compatibility',
);

my $endpoint = Net::QUIC::Endpoint->client(
    local       => pack_sockaddr_in(40035, inet_aton('127.0.0.1')),
    peer        => pack_sockaddr_in(4433, inet_aton('127.0.0.1')),
    alpn        => 'h3',
    server_name => 'localhost',
    transport   => {
        max_datagram_frame_size => 65535,
    },
);

my $h3 = Unblock::HTTP3::Connection->client(
    quic                     => $endpoint->connection,
    enable_http_datagrams    => 1,
    extension_settings       => { 84 => 7 },
    remembered_peer_settings => $state,
);

ok($h3->using_remembered_peer_settings,
    'client starts with remembered peer settings');
ok($h3->peer_extended_connect_enabled,
    'remembered Extended CONNECT capability is available before new SETTINGS');
ok($h3->peer_http_datagrams_enabled,
    'remembered HTTP Datagram capability is available before new SETTINGS');
is($h3->peer_extension_setting(84), '7',
    'remembered generic extension setting is available');
is(
    $h3->{peer_max_field_section_size},
    '65536',
    'remembered peer field-section limit is active',
);

my $local_state = $h3->local_settings_state;
my $local = Unblock::HTTP3::Connection::_decode_settings_state(
    $local_state,
    'local state',
);

is($local->{1}, '4096', 'local state records QPACK table capacity');
is($local->{6}, '65536', 'local state records field-section limit');
is($local->{7}, '100', 'local state records blocked-stream limit');
is($local->{51}, '1', 'local state records HTTP Datagram setting');
is($local->{84}, '7', 'local state records extension setting');

is($h3->peer_settings_state, undef,
    'peer settings state is not exported until current SETTINGS arrive');

done_testing;
