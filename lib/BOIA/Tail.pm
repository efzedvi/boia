package BOIA::Tail;
use strict;
use warnings;

sub new {
	my ($class, @files) = @_;

	if (lc $^O eq 'linux') {
	} elsif ($^O =~ /bsd$/i) {
	} 
	use BOIA::Tail::Generic;
	return BOIA::Tail::Generic->new(@files);
}



1;
