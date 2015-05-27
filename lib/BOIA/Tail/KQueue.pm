package BOIA::Tail::KQueue;
use strict;
use warnings;

use IO::KQueue;
use IO::File;

use BOIA::Log;

use base 'BOIA::Tail::Generic';

sub new {
	my ($class, @files) = @_;

	return undef unless ($^O =~ /bsd$/i);
	my $kq = IO::KQueue->new();
	return undef unless $kq;

	my $self = bless { files => {}, fnos =>{}, roration => {} }, ref($class) || $class;

	$self->{kq} = $kq;
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

	$fd->seek(0, 2) unless ($noseek || exists $self->{roration}->{$file}); # SEEK_END

	if (exists $self->{roration}->{$file}) {
		BOIA::Log->write(LOG_INFO, "re-opening $file");
	}

	eval {
		$self->{kq}->EV_SET(fileno($fd), EVFILT_VNODE, EV_ADD, 
				    NOTE_RENAME | NOTE_DELETE | NOTE_EXTEND | NOTE_WRITE );
	};

	if ($@) {
		BOIA::Log->write(LOG_ERR, $@);
		return undef;
	}

	$self->{files}->{$file} = $fd;
	$self->{fnos}->{fileno($fd)} = $file;
	delete $self->{roration}->{$file} if exists $self->{roration}->{$file};
	return 1;
}

sub close_file {
	my ($self, $file, $possibly_rotated) = @_;

	return undef unless $file;
	if (exists $self->{files}->{$file} && $self->{files}->{$file}) {
		my $fd  = $self->{files}->{$file};
		my $fno = fileno($fd);
		$self->{kq}->EV_SET($fno, EVFILT_VNODE, EV_DELETE);
		delete $self->{fnos}->{$fno} if (exists $self->{fnos}->{$fno});
		$fd->close();
		delete $self->{files}->{$file};
		$self->{roration}->{$file} = 1 if $possibly_rotated;
	}
	return 1;
}

# override-able
sub tail {
	my ($self, $timeout) = @_;

	my $kq = $self->{kq};
	my @events = $kq->kevent($timeout);

	return undef unless scalar(@events);

	# Handle rename and delete events as well as modify
	my $ph = {};
	for my $kevent (@events) {
		next unless ($kevent->[KQ_FILTER] == EVFILT_VNODE);

		my $fno = $kevent->[KQ_IDENT];
		next unless exists $self->{fnos}->{$fno};
		my $file = $self->{fnos}->{$fno};
		my $fd   = $self->{files}->{$file};

		my $fflags = $kevent->[KQ_FFLAGS];
		if ($fflags & (NOTE_EXTEND | NOTE_WRITE)) {
			$ph->{$file} .= join('', $fd->getlines());
		}
		if ($fflags & NOTE_RENAME) {
			BOIA::Log->write(LOG_INFO, "File $file renamed");
			$ph->{$file} .= join('', $fd->getlines()); # read left overs
			$self->close_file($file, 1);
			# wait a bit till the file shows up in case of rotation
			select(undef, undef, undef, 1);
			if ($self->open_file($file, 1)) {
				$fd   = $self->{files}->{$file}; # new fd
				$ph->{$file} .= join('', $fd->getlines());
			}
		}
		if ($fflags & NOTE_DELETE) {
			BOIA::Log->write(LOG_INFO, "File $file deleted");
			$self->close_file($file, 1);
		}
	}

	return $ph;
}

1;

__END__
=head1 NAME

BOIA::Tail::KQueue - BOIA's Tail module implemented on top of IO::KQueue

=head1 SYNOPSIS

	use BOIA::Tail;

	my $tail = BOIA::Tail->new(@files);
	$tail->tail($timeout);

=head1 DESCRIPTION

It helps BOIA tail files using IO::KQueue

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
