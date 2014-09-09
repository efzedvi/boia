package BOIA;
use strict;
use warnings;

use BOIA::Config;

use File::Tail;

sub new 
{
	my ($class, $arg) = @_;

	my $to_bless = $arg;
	$to_bless = {} if (ref($arg) eq 'HASH' || !$arg);

	my $self = bless $to_bless, ref($class) || $class;

	$self->{cfg} = BOIA::Config->new($arg);
	#if ($self->{cfg}) {
	#}

	return $self;
}

sub run {
	my ($self) = @_;

}

1
