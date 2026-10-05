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

    use Unblock::HTTP3::Server;

    my $server = Unblock::HTTP3::Server->new(
        quic => $quic,
        on_request => sub {
            my ($transaction, $request) = @_;
            ...
        },
    );

    $server->start;

=head1 DESCRIPTION

A Server owns HTTP/3 protocol state for one existing Net::QUIC connection.

It does not own a listening socket, UDP socket, TLS, timers, or an event loop.

C<on_request>, C<on_body>, C<on_request_end>, and C<on_error> provide the
common Unblock server callback vocabulary. The existing pull interface remains
available for integrations that prefer it.

=head1 SEE ALSO

L<Unblock::HTTP3>, L<Unblock::HTTP3::Transaction>

=head1 LICENSE

MIT License.

=cut
