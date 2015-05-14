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

	my $self = bless { files => {} }, ref($class) || $class;

	$self->{inotify} = $inotify;
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

	my $wd = $self->{inotify}->watch($file, IN_MODIFY | IN_MOVE_SELF | IN_DELETE_SELF)
			or die "watch creation failed";
	$self->{files}->{$file} = { fd => $fd, wd => $wd};
}

sub close_file {
	my ($self, $file) = @_;

	if (exists $self->{files}->{$file} && $self->{files}->{$file}) {
		my $fd  = $self->{files}->{$file}->{fd};
		my $wd  = $self->{files}->{$file}->{wd};
		$fd->close();
		$wd->cancel();
		delete $self->{files}->{$file};
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

	my $nfound = select($rout=$rin, undef, undef, $timeout);
	if ($nfound) {
		my @events = $inotify->read;
		return undef unless scalar(@events);

		# Handle rename and delete events as well as modify
		my $ph = {};
		for my $event (@events) {
			my $file = $event->fullname;
			if ($event->IN_MODIFY) {
				if (exists $self->{files}->{$file} && 
				    exists $self->{files}->{$file}->{fd}) {
					$ph->{$file} = $self->{files}->{$file}->{fd};
				}
			}

			if ($event->IN_MOVE_SELF) {
				$self->close_file($file);
				# wait a bit till the file shows up in case of rotation
				select(undef, undef, undef, 1);
				$self->open_file($file, 1);
			}

			if ($event->IN_DELETE_SELF) {
				delete $self->{files}->{$file};
			}
		}

		return $ph;
	}
	return undef;
}

1;
