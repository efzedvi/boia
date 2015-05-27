package BOIA::Tail::Generic;
use strict;
use warnings;

use File::Tail;
use IO::File;

use BOIA::Log;

sub new {
	my ($class, @files) = @_;

	my $self = bless { files => {} }, ref($class) || $class;

	$self->set_files(@files);

	return $self;
}

# override-able
sub open_file {
	my ($self, $file) = @_;

	if ( !$file || ! -f $file || ! -r $file ) {
		BOIA::Log->write(LOG_ERR, "Failed openning $file");
		return undef;
	}

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
__END__
=head1 NAME

BOIA::Tail::Generic - BOIA's Tail module implemented using File::Tail

=head1 SYNOPSIS

	use BOIA::Tail;

	my $tail = BOIA::Tail::Generic->new(@files);
	$tail->tail($timeout);

=head1 DESCRIPTION

It uses File::Tail, and it's slow, but works on many operating systems.

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

