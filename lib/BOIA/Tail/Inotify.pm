package BOIA::Tail::Inotify;
use strict;
use warnings;

use Linux::Inotify2;
use IO::File;

use BOIA::Log;

use base 'BOIA::Tail::Generic';

sub new {
	my ($class, @files) = @_;

	return undef unless ($^O eq 'linux');
	my $inotify = Linux::Inotify2->new();
	return undef unless $inotify;

	my $self = bless { files => {}, rotation => {} }, ref($class) || $class;

	$self->{inotify} = $inotify;
	$self->set_files(@files);

	return $self;
}

# override-able
sub open_file {
	my ($self, $file, $noseek) = @_;

	my $fd  = IO::File->new($file, 'r');
	if ( !$fd ) {
		BOIA::Log->write(LOG_ERR, "Failed openning $file");
		return undef;
	}

	$fd->seek(0, 2) unless ($noseek || exists $self->{rotation}->{$file}); # SEEK_END

	if (exists $self->{rotation}->{$file}) {
		BOIA::Log->write(LOG_INFO, "re-opening $file");
	}

	my $wd = $self->{inotify}->watch($file, IN_MODIFY | IN_MOVE_SELF | IN_DELETE_SELF |
						IN_ATTRIB | IN_IGNORED | IN_UNMOUNT);
	if (!$wd) {
		BOIA::Log->write(LOG_ERR, "watch creation failed");
		die "watch creation failed";
	}
	# Unfortunately Inotify doesn't report the file deletion if you have the file open
	# it will only report the meta data change which is pretty stupid. We have to 
	# keep the inode to see if it was deleted and recreated again, not perfect, but
	# better than nothing for now
	my @stat = stat $file;
	$self->{files}->{$file} = { fd => $fd, wd => $wd, inode => $stat[1]};
	delete $self->{rotation}->{$file} if exists $self->{rotation}->{$file};
	return 1;
}

sub close_file {
	my ($self, $file, $possibly_rotated) = @_;

	return undef unless $file;
	if (exists $self->{files}->{$file} && $self->{files}->{$file}) {
		my $fd  = $self->{files}->{$file}->{fd};
		my $wd  = $self->{files}->{$file}->{wd};
		$fd->close();
		$wd->cancel();
		delete $self->{files}->{$file};
		$self->{rotation}->{$file} = 1 if $possibly_rotated;
	}
	return 1;
}

# override-able
sub tail {
	my ($self, $timeout) = @_;

	my $inotify = $self->{inotify};
	my $rin =  '';
	my $rout;
	vec($rin, $inotify->fileno(), 1) = 1;

	my $nfound;
	eval { $nfound = select($rout=$rin, undef, undef, $timeout); };

	if ($@ && ($! ne 'Interrupted system call')) {
		BOIA::Log->write(LOG_INFO, "select() returned an error: $@ : $!");
	}

	if ($nfound>0) {
		my @events = $inotify->read;
		return undef unless scalar(@events);

		# Handle rename and delete events as well as modify
		my $ph = {};
		for my $event (@events) {
			my $file = $event->fullname;
			my $fd;

			if ($file && exists $self->{files}->{$file} && 
			    exists $self->{files}->{$file}->{fd}) {
				$fd = $self->{files}->{$file}->{fd};
			} else {
				BOIA::Log->write(LOG_INFO, "Got an event for unmonitored $file");
				next;
			}

			if ($event->IN_MODIFY) {
				$ph->{$file} .= join('', $fd->getlines());
			}

			my $close_reopen = 0;

			if ($event->IN_MOVE_SELF) {
				BOIA::Log->write(LOG_INFO, "File $file renamed");
				$close_reopen = 1;
				$ph->{$file} .= join('', $fd->getlines()); # possible left overs
			}

			if ($event->IN_DELETE_SELF || 
			    $event->IN_IGNORED || $event->IN_UNMOUNT) {
				BOIA::Log->write(LOG_INFO, "File $file deleted");
				$close_reopen = 1;
			}

			if ($event->IN_ATTRIB) {
				my @stat = stat $file;
				if (! -e $file || $self->{files}->{$file}->{inode} != $stat[1]) {
					BOIA::Log->write(LOG_INFO, "File $file deleted");
					$close_reopen = 1;
				} elsif (! -r $file) {
					BOIA::Log->write(LOG_INFO, "Permission revoked for $file");
					$self->close_file($file);
				}
			}

			if ($close_reopen) {
				$self->close_file($file, 1);
				# wait a bit till the file shows up in case of rotation
				select(undef, undef, undef, 1);
				if ($self->open_file($file, 1)) {
					$fd = $self->{files}->{$file}->{fd}; # new fd
					$ph->{$file} .= join('', $fd->getlines());
				}
			}
		}
		return $ph;
	}
	return undef;
}

1;

__END__
=head1 NAME

BOIA::Tail::Inotify - BOIA's Tail module implemented on top of Linux::Inotify2

=head1 SYNOPSIS

	use BOIA::Tail;

	my $tail = BOIA::Tail->new(@files);
	$tail->tail($timeout);

=head1 DESCRIPTION

It helps BOIA tail files using Linux::Inotify2.

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
