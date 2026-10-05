package Unblock::HTTP3::Server;

use strict;
use warnings;

use parent 'Unblock::HTTP3::Connection';

our $VERSION = '0.10';

sub new {
    my ($class, %option) = @_;
    return $class->_new('server', %option);
}

1;

__END__

=head1 NAME

Unblock::HTTP3::Server - one server HTTP/3 connection

=head1 SYNOPSIS

    use Uniform::HTTP::Response;
    use Unblock::HTTP3::Server;

    my $server = Unblock::HTTP3::Server->new(
        quic => $quic,

        on_request => sub {
            my ($transaction, $request) = @_;

            $transaction->respond(
                Uniform::HTTP::Response->new(
                    status => 200,
                    body   => "hello\n",
                ),
            );
        },
    );

    $server->start;

=head1 DESCRIPTION

A Server owns HTTP/3 protocol state for one existing L<Net::QUIC> connection.

It does not own a listening socket, UDP socket, TLS, timers, or an event loop.

The common request callbacks are:

    on_request
    on_body
    on_request_end
    on_error

C<on_request_end> is a lifecycle callback. It does not change whether request
bodies are buffered or streamed.

Use C<send_informational()> for a 1xx response and C<respond()> for the final
response. Pass C<stream_body =E<gt> 1> to C<respond()> to produce the response
body with C<write()> and C<end()>.

The pull interface remains available through C<next_transaction()>.

=head1 SEE ALSO

L<Unblock::HTTP3>, L<Unblock::HTTP3::Transaction>,
L<Uniform::HTTP::Response>

=head1 LICENSE

MIT License.

=cut
