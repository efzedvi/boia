package BOIA::Tail::Inotify;
use strict;
use warnings;

use Linux::Inotify2;
use IO::File;

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

	my $log = BOIA::Log->new();

	my $fd  = IO::File->new($file, 'r');
	if ( !$fd ) {
		$log->write(LOG_ERR, "Failed openning $file");
		return undef;
	}

	$fd->seek(0, 2) unless ($noseek || exists $self->{rotation}->{$file}); # SEEK_END

	if (exists $self->{roration}->{$file}) {
		$log->write(LOG_INFO, "re-opening $file");
	}

	my $wd = $self->{inotify}->watch($file, IN_MODIFY | IN_MOVE_SELF | IN_DELETE_SELF | 
						IN_CLOSE_WRITE);
	if (!$wd) {
		$log->write(LOG_ERR, "watch creation failed");
		die "watch creation failed";
	}
	$self->{files}->{$file} = { fd => $fd, wd => $wd};
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

	my $log = BOIA::Log->new();

	my $nfound = select($rout=$rin, undef, undef, $timeout);
	if ($nfound) {
		my @events = $inotify->read;
		return undef unless scalar(@events);

		# Handle rename and delete events as well as modify
		my $ph = {};
		for my $event (@events) {
			my $file = $event->fullname;
			my $fd = $self->{files}->{$file}->{fd};
			if ($event->IN_MODIFY || $event->IN_CLOSE_WRITE) {
				if (exists $self->{files}->{$file} && 
				    exists $self->{files}->{$file}->{fd}) {
					$ph->{$file} .= join('', $fd->getlines());
				}
			}

			if ($event->IN_MOVE_SELF) {
				$log->write(LOG_INFO, "File $file renamed");
				$ph->{$file} .= join('', $fd->getlines()); # possible left overs
				$self->close_file($file, 1);
				# wait a bit till the file shows up in case of rotation
				select(undef, undef, undef, 1);
				if ($self->open_file($file, 1)) {
					$fd = $self->{files}->{$file}->{fd}; # new fd
					$ph->{$file} .= join('', $fd->getlines());
				}
			}

			if ($event->IN_DELETE_SELF) {
				$log->write(LOG_INFO, "File $file deleted");
				$self->close_file($file, 1);
			}
		}
		return $ph;
	}
	return undef;
}

1;
