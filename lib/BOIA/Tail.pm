package BOIA::Tail;
use strict;
use warnings;

use BOIA::Log;

sub new {
	my ($class, @files) = @_;

	if (lc $^O eq 'linux') {
		eval "use BOIA::Tail::Inotify;";
		if (!$@) {
			BOIA::Log->write(LOG_INFO, 'Using BOIA::Tail::Inotify');
			return BOIA::Tail::Inotify->new(@files);
		}
	} elsif ($^O =~ /bsd$/i) {
		eval "use BOIA::Tail::KQueue;";
		if (!$@) {
			BOIA::Log->write(LOG_INFO, 'Using BOIA::Tail::KQueue');
			return BOIA::Tail::KQueue->new(@files);
		}
	} 
	use BOIA::Tail::Generic;
	BOIA::Log->write(LOG_INFO, 'Using BOIA::Tail::Generic');
	return BOIA::Tail::Generic->new(@files);
}

1;
__END__
=head1 NAME

BOIA::Tail - BOIA's Tail module

=head1 SYNOPSIS

	use BOIA::Tail;

	my $tail = BOIA::Tail->new(@files);
	$tail->tail($timeout);

=head1 DESCRIPTION

This module is a front end for BOIA::Generic, BOIA::KQueue, and BOIA::Inotify.
It returns an appropriate instances of the mentioned modules based on the operating
system and the availability of other needed modules.

=head1 METHODS


=head2 new ( @files )


=head2 set_files( @files )


=head2 tail( $timeout )


=head1 AUTHOR

Faraz Vahabzadeh C<< <faraz@fzv.ca> >>

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2015, Faraz Vahabzadeh.  All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.

=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.
