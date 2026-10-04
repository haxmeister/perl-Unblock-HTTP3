package Unblock::HTTP3;

use strict;
use warnings;

use XSLoader ();

our $VERSION = '0.01';

XSLoader::load(__PACKAGE__, $VERSION);

1;

__END__

=head1 NAME

Unblock::HTTP3 - HTTP/3 engine for Perl

=head1 DESCRIPTION

Unblock::HTTP3 is an HTTP/3 protocol engine designed to remain operating-system and event-loop neutral.

It uses libnghttp3 through Alien::nghttp3 for HTTP/3 framing and QPACK and
uses Net::QUIC for QUIC transport.

Unblock::HTTP3 does not own UDP sockets, timers, or an event loop. The event-loop
adapter remains below Net::QUIC.

The public request and response classes follow the Uniform::HTTP message
contract.

=head1 AUTHOR

Joshua S. Day

=head1 LICENSE

This software is available under the MIT License.

=cut
