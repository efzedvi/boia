package BOIA::Tail::KQueue;
use strict;
use warnings;

use Sys::Syslog qw(:macros);
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

	my $log = BOIA::Log->new();

	my $fd  = IO::File->new($file, 'r');
	if ( !$fd ) {
		$log->write(LOG_ERR, "Failed openning $file");
		return undef;
	}

	$fd->seek(0, 2) unless ($noseek || exists $self->{roration}->{$file}); # SEEK_END

	if (exists $self->{roration}->{$file}) {
		$log->write(LOG_INFO, "re-opening $file");
	}

	eval {
		$self->{kq}->EV_SET(fileno($fd), EVFILT_VNODE, EV_ADD, 
				    NOTE_RENAME | NOTE_DELETE | NOTE_EXTEND | NOTE_WRITE );
	};

	if ($@) {
		$log->write(LOG_ERR, $@);
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

	my $log = BOIA::Log->new();
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
			$log->write(LOG_INFO, "File $file renamed");
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
			$log->write(LOG_INFO, "File $file deleted");
			$self->close_file($file, 1);
		}
	}

	return $ph;
}

1;
