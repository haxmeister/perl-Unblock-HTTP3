package Unblock::HTTP3::Client;

use strict;
use warnings;
use Carp qw(croak);
use Uniform::HTTP::Request 0.06 ();

use parent 'Unblock::HTTP3::Connection';

our $VERSION = '0.10';

sub new {
    my ($class, %option) = @_;
    return $class->_new('client', %option);
}

sub request {
    my ($self, @arg) = @_;

    my ($request, %option);
    if (@arg && ref($arg[0])) {
        $request = shift @arg;
        croak 'request(): options must be key/value pairs' if @arg % 2;
        %option = @arg;
    } else {
        croak 'request(): fields must be key/value pairs' if @arg % 2;
        my %field = @arg;
        for my $name (qw(
            stream_body receive_body datagrams early_data
            on_informational on_response on_body on_complete on_error on_drain
        )) {
            $option{$name} = delete $field{$name} if exists $field{$name};
        }
        $request = Uniform::HTTP::Request->new(%field);
    }

    return $self->SUPER::request($request, %option);
}

1;

__END__

=head1 NAME

Unblock::HTTP3::Client - one client HTTP/3 connection

=head1 SYNOPSIS

    use Unblock::HTTP3::Client;

    my $client = Unblock::HTTP3::Client->new(
        quic => $quic,
    );

    $client->start;

    my $transaction = $client->request(
        method    => 'GET',
        target    => '/',
        scheme    => 'https',
        authority => 'example.com',

        on_response => sub {
            my ($transaction, $response) = @_;
        },

        on_body => sub {
            my ($transaction, $response, $bytes) = @_;
        },

        on_complete => sub {
            my ($transaction) = @_;
        },
    );

=head1 DESCRIPTION

A Client owns HTTP/3 protocol state for one existing L<Net::QUIC> connection.

It does not own UDP sockets, TLS, timers, or an event loop.

C<request()> accepts named Uniform HTTP request fields or an existing
Uniform-compatible Request object and returns an
L<Unblock::HTTP3::Transaction>.

    $client->request(
        method => 'GET', target => '/', scheme => 'https',
        authority => 'example.com', on_response => sub { ... },
    );

    $client->request($uniform_request, on_response => sub { ... });

When named fields are used, HTTP/3 request options and callbacks are separated
from message fields before building the Uniform Request. This includes
C<stream_body>, C<receive_body>, C<datagrams>, and C<early_data>.
HTTP/3 validation remains in the connection engine.

Useful per-request callbacks are:

    on_informational
    on_response
    on_body
    on_complete
    on_error
    on_drain

Pass C<stream_body =E<gt> 1> to produce a request body with the Transaction
C<write()> and C<end()> methods.

The pull interface remains available through C<next_transaction()> and
C<next_informational()>.

=head1 SEE ALSO

L<Unblock::HTTP3>, L<Unblock::HTTP3::Transaction>,
L<Uniform::HTTP::Request>

=head1 LICENSE

MIT License.

=cut
