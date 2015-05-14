package BOIA::Tail;
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
	my ($self, $file) = @_;

	return undef unless ( -f $file && -r $file );

	my $fd  = IO::File->new($file, 'r');
	$fd->seek(0, 2); # SEEK_END
	
	my $wd = $self->{inotify}->watch($file, IN_MODIFY | IN_MOVE_SELF | IN_DELETE_SELF)
			or die "watch creation failed" ;
	$self->{files}->{$file} = { fd => $fd, wd => $wd);
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

sub set_files {
	my ($self, @files) = @_;

	my %new_files = map { $_ => 1 } @files;

	# add the files that are not in the current list
	foreach my $file (@files) {
		if (! exists $self->{files}->{$file}) {
			$self->open_file($file);
		}
	}

	# delete the files in the current list that are not in the new list
	foreach my $file (keys %{ $self->{files} }) {
		if (! exists $new_files{$file} ) {
			$self->close_file($file);
		}
	}
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

		#TODO : handle rename and delete events as well as modify

		#my %ph = map { $_->input() => $_->{handle} } @pending;
		#return \%ph;
	}
	return undef;
}

1;
