use strict;
use warnings;

use Test2::V0;

use Unblock::HTTP3::Client;
use Unblock::HTTP3::Connection;
use Unblock::HTTP3::NativeABI;
use Unblock::HTTP3::Server;
use Unblock::HTTP3::Transaction;

ok(Unblock::HTTP3::Client->can('new'), 'Client has new()');
ok(Unblock::HTTP3::Server->can('new'), 'Server has new()');

ok(!Unblock::HTTP3::Connection->can('client'),
    'legacy Connection->client() is removed');
ok(!Unblock::HTTP3::Connection->can('server'),
    'legacy Connection->server() is removed');

for my $method (qw(
    state error is_complete is_cancelled is_error is_terminal
    respond write end send_informational
)) {
    ok(Unblock::HTTP3::Transaction->can($method),
        "Transaction has $method()");
}

ok(!Unblock::HTTP3::Transaction->can('send_response'),
    'legacy send_response() is removed');

for my $method (qw(definition native_include_dir header_path c_header)) {
    ok(Unblock::HTTP3::NativeABI->can($method),
        "NativeABI has $method()");
}

my $definition = Unblock::HTTP3::NativeABI::definition();
ok(defined $definition->{provider}, 'NativeABI definition reports provider');
is($definition->{abi_version}, 1, 'NativeABI version remains 1');
ok($definition->{struct_size} > 0, 'NativeABI definition reports struct_size');
ok($definition->{operations_address},
    'NativeABI definition reports operations_address');

done_testing;
