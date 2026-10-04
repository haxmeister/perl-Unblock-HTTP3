use strict;
use warnings;

use Test2::V0;
use Uniform::HTTP::Request;
use Uniform::HTTP::Response;

use Unblock::HTTP3::Request;
use Unblock::HTTP3::Response;

my @message_methods = qw(
    version header header_values header_count header_name header_value
    add_header remove_header body has_buffered_body is_complete is_mutable
    headers_are_lossless
);

my @transport_methods = qw(
    send write respond receive parse serialize socket connection transaction
    stream pause resume drain cancel retry redirect
);

for my $class (qw(Unblock::HTTP3::Request Unblock::HTTP3::Response)) {
    for my $method (@message_methods) {
        ok($class->can($method), "$class provides Uniform method $method");
    }

    for my $method (@transport_methods) {
        ok(!$class->can($method),
            "$class does not own transport method $method");
    }
}

my $uniform_request = Uniform::HTTP::Request->new(
    method  => 'POST',
    target  => '/items?draft=1',
    version => '3',
    headers => [
        [ 'X-First', 'one' ],
        [ 'X-Test',  'one' ],
        [ 'x-test',  'two' ],
        [ 'X-Last',  'four' ],
    ],
    body => '',
);

my $http3_request = Unblock::HTTP3::Request->new(
    method    => 'POST',
    target    => '/items?draft=1',
    scheme    => 'https',
    authority => 'example.com',
    version   => '3',
    headers   => [
        [ 'X-First', 'one' ],
        [ 'X-Test',  'one' ],
        [ 'x-test',  'two' ],
        [ 'X-Last',  'four' ],
    ],
    body => '',
);

for my $method (qw(method target version body header_count)) {
    is(
        $http3_request->$method(),
        $uniform_request->$method(),
        "request $method follows Uniform behavior",
    );
}

is(
    $http3_request->header('X-TEST'),
    $uniform_request->header('X-TEST'),
    'request header lookup is case insensitive',
);

is(
    $http3_request->header_values('x-test'),
    $uniform_request->header_values('x-test'),
    'request repeated headers preserve values in order',
);

is(
    [ map { $http3_request->header_name($_) }
        0 .. $http3_request->header_count - 1 ],
    [ map { $uniform_request->header_name($_) }
        0 .. $uniform_request->header_count - 1 ],
    'request preserves header occurrence order and spelling',
);

is($http3_request->header_name(50), undef,
    'request out-of-range header index returns undef');
ok($http3_request->target_is_exact, 'request target is exact');
ok($http3_request->headers_are_lossless, 'request headers are lossless');
ok($http3_request->has_buffered_body,
    'empty request body is still a buffered body');
is($http3_request->body, '', 'empty request body is retained');
ok($http3_request->is_complete, 'constructed request is complete');
ok($http3_request->is_mutable, 'constructed request is mutable');

is($http3_request->method('PATCH'), $http3_request,
    'request method setter is chainable');
is($http3_request->method, 'PATCH', 'request method setter changes method');
is($http3_request->target('*'), $http3_request,
    'request target setter is chainable');
is($http3_request->target, '*', 'asterisk request target is accepted');

is($http3_request->header('X-Test', 'replacement'), $http3_request,
    'request header setter is chainable');
is(
    $http3_request->header_values('x-test'),
    ['replacement'],
    'request header setter replaces every matching occurrence',
);
is(
    [ map { $http3_request->header_name($_) }
        0 .. $http3_request->header_count - 1 ],
    [ 'X-First', 'X-Test', 'X-Last' ],
    'replacement occupies the first matching header position',
);

is($http3_request->add_header('X-First', 'two'), $http3_request,
    'request add_header is chainable');
is(
    $http3_request->header_values('x-first'),
    [ 'one', 'two' ],
    'request add_header appends a duplicate occurrence',
);
is($http3_request->remove_header('X-FIRST'), $http3_request,
    'request remove_header is chainable');
is($http3_request->header_values('x-first'), [],
    'request remove_header removes every occurrence');

is($http3_request->version(2), $http3_request,
    'request version setter is chainable');
is($http3_request->version, '2', 'numeric request version becomes bytes');
is($http3_request->version(undef), $http3_request,
    'request version can be cleared');
is($http3_request->version, undef, 'cleared request version is undef');

is($http3_request->scheme, 'https', 'request exposes HTTP/3 scheme');
is($http3_request->authority, 'example.com',
    'request exposes HTTP/3 authority');

my $request_without_body = Unblock::HTTP3::Request->new(
    method => 'GET',
    target => '/',
);

ok(!$request_without_body->has_buffered_body,
    'omitted request body has no buffer');
is($request_without_body->body, undef,
    'omitted request body returns undef');
is($request_without_body->body('bytes'), $request_without_body,
    'request body setter is chainable');
ok($request_without_body->has_buffered_body,
    'request body setter installs a buffer');

my $uniform_response = Uniform::HTTP::Response->new(
    status  => 204,
    version => '3',
    headers => [
        [ 'X-Test', 'yes' ],
    ],
);

my $http3_response = Unblock::HTTP3::Response->new(
    status  => 204,
    version => '3',
    headers => [
        [ 'X-Test', 'yes' ],
    ],
);

for my $method (qw(status version header_count)) {
    is(
        $http3_response->$method(),
        $uniform_response->$method(),
        "response $method follows Uniform behavior",
    );
}

is($http3_response->reason, undef,
    'HTTP/3 response does not synthesize a reason phrase');
is($http3_response->status(299), $http3_response,
    'response status setter is chainable');
is($http3_response->status, 299, 'response status setter changes status');
is($http3_response->reason('Custom'), $http3_response,
    'response reason setter is chainable');
is($http3_response->reason, 'Custom',
    'response reason is retained for cross-version use');
is($http3_response->reason(undef), $http3_response,
    'response reason can be cleared');
is($http3_response->reason, undef, 'cleared response reason is undef');
ok($http3_response->headers_are_lossless, 'response headers are lossless');
ok(!$http3_response->has_buffered_body,
    'response with omitted body has no body buffer');
ok($http3_response->is_complete, 'constructed response is complete');
ok($http3_response->is_mutable, 'constructed response is mutable');

my $immutable = Unblock::HTTP3::Response->new(
    status  => 200,
    headers => [ [ 'X-Test', 'before' ] ],
);

$immutable->_commit;

ok(!$immutable->is_mutable, 'committed response is immutable');
like(
    dies { $immutable->header('X-Test', 'after') },
    qr/message is immutable/,
    'immutable response rejects header mutation',
);
is($immutable->header('X-Test'), 'before',
    'failed immutable mutation changes nothing');

done_testing;
