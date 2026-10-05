package Unblock::HTTP3::Client;

use strict;
use warnings;

use parent 'Unblock::HTTP3::Connection';

our $VERSION = '0.10';

sub new {
    my ($class, %option) = @_;
    return $class->_new('client', %option);
}

1;

__END__

=head1 NAME

Unblock::HTTP3::Client - one client HTTP/3 connection

=head1 SYNOPSIS

    use Uniform::HTTP::Request;
    use Unblock::HTTP3::Client;

    my $client = Unblock::HTTP3::Client->new(
        quic => $quic,
    );

    $client->start;

    my $transaction = $client->request(
        Uniform::HTTP::Request->new(
            method    => 'GET',
            target    => '/',
            scheme    => 'https',
            authority => 'example.com',
        ),

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

C<request()> accepts the Uniform HTTP request contract and returns an
L<Unblock::HTTP3::Transaction>.

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
