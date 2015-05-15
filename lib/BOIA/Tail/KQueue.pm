package BOIA::Tail::KQueue;
use strict;
use warnings;

use IO::KQueue;
use IO::File;

use base 'BOIA::Tail::Generic';

sub new {
	my ($class, @files) = @_;

	return undef unless ($^O =~ /bsd$/i);
	my $kq = IO::KQueue->new();
	return undef unless $kq;

	my $self = bless { files => {}, fnos =>{} }, ref($class) || $class;

	$self->{kq} = $kq;
	$self->set_files(@files);

	return $self;
}

# override-able
sub open_file {
	my ($self, $file, $noseek) = @_;

	return undef unless ( -f $file && -r $file );

	my $fd  = IO::File->new($file, 'r');
	return undef unless $fd;
	$fd->seek(0, 2) unless $noseek; # SEEK_END

	eval {
		$self->{kq}->EV_SET(fileno($fd), EVFILT_READ, EV_ADD);
		$self->{kq}->EV_SET(fileno($fd), EVFILT_VNODE, EV_ADD, NOTE_RENAME | NOTE_DELETE | NOTE_EXTEND | NOTE_WRITE );
	};

	return undef if $@;

	$self->{files}->{$file} = $fd;
	$self->{fnos}->{fileno($fd)} = $file;
}

sub close_file {
	my ($self, $file) = @_;

	if (exists $self->{files}->{$file} && $self->{files}->{$file}) {
		my $fd  = $self->{files}->{$file};
		my $fno = fileno($fd);
		delete $self->{fnos}->{$fno} if (exists $self->{fnos}->{$fno});
		$fd->close();
		delete $self->{files}->{$file};
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
		my $fno = $kevent->[KQ_IDENT];
		next unless exists $self->{fnos}->{$fno};
		my $file = $self->{fnos}->{$fno};

		if ($kevent->[KQ_FILTER] == EVFILT_READ) {
			$ph->{$file} = $self->{files}->{$file};
		} elsif ($kevent->[KQ_FILTER] == EVFILT_VNODE) {
			my $fflags = $kevent->[KQ_FFLAGS];
			if ($fflags & (NOTE_EXTEND | NOTE_WRITE)) {
				$ph->{$file} = $self->{files}->{$file};
			}
			if ($fflags & NOTE_DELETE) {
				$self->close_file($file);
			}
			if ($fflags & NOTE_RENAME) {
				$self->close_file($file);
				# wait a bit till the file shows up in case of rotation
				select(undef, undef, undef, 1);
				$self->open_file($file, 1);
			}
		} else {
			next;
		}
	}

	return $ph;
}

1;
