package BOIA::Tail::Generic;
use strict;
use warnings;

use File::Tail;
use IO::File;

sub new {
	my ($class, @files) = @_;

	my $self = bless { files => {} }, ref($class) || $class;

	$self->set_files(@files);

	return $self;
}

# override-able
sub open_file {
	my ($self, $file) = @_;

	return undef unless ( $file && -f $file && -r $file );

	my $ft  = File::Tail->new( name => $file );
	$self->{files}->{$file} = $ft;

	$self->{fnos}->{fileno($ft->{handle})} = $file;
}

# override-able
sub close_file {
	my ($self, $file) = @_;

	return undef unless $file;
	if (exists $self->{files}->{$file} && $self->{files}->{$file}) {
		my $fd  = $self->{files}->{$file};
		my $fno = fileno($fd->{handle});
		delete $self->{fnos}->{$fno} if (exists $self->{fnos}->{$fno});
		close($fd->{handle});
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

	my @files = values %{ $self->{files} };

	my ($nfound, $timeleft, @pending) = 
		File::Tail::select(undef, undef, undef, $timeout, @files);
	if (scalar(@pending)) {
		my %ph = map { $_->input() => join('', $_->read) } @pending;
		return \%ph;
	}
	return undef;
}

1;
