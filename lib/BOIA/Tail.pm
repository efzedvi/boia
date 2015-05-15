package BOIA::Tail;
use strict;
use warnings;

sub new {
	my ($class, @files) = @_;

	if (lc $^O eq 'linux') {
		eval "use BOIA::Tail::Inotify;";
		if (!$@) {
			return BOIA::Tail::Inotify->new(@files);
		}
	} elsif ($^O =~ /bsd$/i) {
		eval "use BOIA::Tail::KQueue;";
		if (!$@) {
			return BOIA::Tail::KQueue->new(@files);
		}
	} 
	use BOIA::Tail::Generic;
	return BOIA::Tail::Generic->new(@files);
}

1;
