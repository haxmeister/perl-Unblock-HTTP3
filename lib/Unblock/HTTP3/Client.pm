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

    use Unblock::HTTP3::Client;

    my $client = Unblock::HTTP3::Client->new(
        quic => $quic,
    );

    $client->start;

=head1 DESCRIPTION

A Client owns HTTP/3 protocol state for one existing Net::QUIC connection.

It does not own UDP sockets, TLS, timers, or an event loop.

Use C<request()> to create L<Unblock::HTTP3::Transaction> objects.

=head1 SEE ALSO

L<Unblock::HTTP3>, L<Unblock::HTTP3::Transaction>

=head1 LICENSE

MIT License.

=cut
