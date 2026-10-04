use strict;
use warnings;

use Test2::V0;

use Unblock::HTTP3::Connection;

my $request = Unblock::HTTP3::Connection::_received_request(
    {
        method    => 'GET',
        target    => '/',
        scheme    => 'https',
        authority => 'example.test',
        protocol  => undef,
        headers   => [
            [ 'cookie', 'a=1' ],
            [ 'x-middle', 'preserved' ],
            [ 'cookie', 'b=2' ],
            [ 'cookie', 'c=3; d=4' ],
        ],
    },
    1,
);

is(
    $request->header_values('cookie'),
    [ 'a=1; b=2; c=3; d=4' ],
    'received HTTP/3 Cookie field lines are coalesced for generic applications',
);

is(
    [
        map {
            [
                $request->header_name($_),
                $request->header_value($_),
            ]
        } 0 .. $request->header_count - 1
    ],
    [
        [ 'cookie',   'a=1; b=2; c=3; d=4' ],
        [ 'x-middle', 'preserved' ],
    ],
    'Cookie coalescing keeps the first field position and preserves other fields',
);

my $single = Unblock::HTTP3::Connection::_received_request(
    {
        method    => 'GET',
        target    => '/',
        scheme    => 'https',
        authority => 'example.test',
        protocol  => undef,
        headers   => [
            [ 'cookie', 'one=1' ],
            [ 'x-test', 'value' ],
        ],
    },
    1,
);

is(
    $single->header_values('cookie'),
    [ 'one=1' ],
    'a single Cookie field line is unchanged',
);

my $response = Unblock::HTTP3::Connection::_received_response(
    200,
    [
        [ 'cookie', 'response-one=1' ],
        [ 'cookie', 'response-two=2' ],
    ],
    0,
);

is(
    $response->header_values('cookie'),
    [ 'response-one=1; response-two=2' ],
    'Cookie normalization applies to any decompressed HTTP/3 field section',
);

$response->add_trailer('cookie', 'trailer-one=1');
$response->add_trailer('x-trailer', 'preserved');
$response->add_trailer('cookie', 'trailer-two=2');

ok(
    Unblock::HTTP3::Connection::_coalesce_trailer_cookie_fields(
        $response,
    ),
    'multiple trailer Cookie field lines require coalescing',
);

is(
    $response->trailer_values('cookie'),
    [ 'trailer-one=1; trailer-two=2' ],
    'trailer Cookie field lines use the RFC delimiter',
);

is(
    [
        map {
            [
                $response->trailer_name($_),
                $response->trailer_value($_),
            ]
        } 0 .. $response->trailer_count - 1
    ],
    [
        [ 'cookie',    'trailer-one=1; trailer-two=2' ],
        [ 'x-trailer', 'preserved' ],
    ],
    'trailer Cookie coalescing preserves field ordering',
);

done_testing;
