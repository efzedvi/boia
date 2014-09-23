package BOIA;
use strict;
use warnings;

use BOIA::Config;

use File::Tail;

our $version = '0.1';

sub new 
{
	my ($class, $arg) = @_;

	my $to_bless = $arg;
	$to_bless = {} if (ref($arg) eq 'HASH' || !$arg);

	my $self = bless $to_bless, ref($class) || $class;

	$self->{cfg} = BOIA::Config->new($arg);
	return undef unless $self->{cfg};

	return $self;
}

sub version {
	my ($self) = @_;
	
	return $version;
}

sub run {
	my ($self, $is_daemon) = @_;

}

sub read_config {
	my ($self) = @_;

	return $self->{cfg}->read() if defined $self->{cfg};
	return undef;
}

sub exit_loop {
	my ($self) = @_;

	return unless ($self && ref($self));
	$self->{keep_going} = 0;
}


1
