package BOIA;
use strict;
use warnings;

use IO::File;
use File::Tail;

use BOIA::Config;

our $version = '0.1';

sub new {
	my ($class, $arg) = @_;

	my $to_bless = $arg;
	$to_bless = {} if (ref($arg) eq 'HASH' || !$arg);

	my $self = bless $to_bless, ref($class) || $class;

	$self->{cfg} = BOIA::Config->new($arg);
	return undef unless $self->{cfg};

	return $self;
}

sub version {
	return $version;
}

sub run {
	my ($self, $is_daemon) = @_;

	$self->{keep_going} = 1;

	my $result = $self->read_config();
	my $active_logs = $self->{cfg}->{active_sections};
	return undef if scalar( @{ $result->{errors} } ) || !scalar(@$active_logs);

	while ($self->{keep_going}) {
		if (defined $self->{cfg_reloaded}) {
			$self->{cfg_reloaded} = undef;
			$active_logs = $self->{cfg}->{active_sections};
			last if !scalar(@$active_logs);
		}
		
		my @files = ();
		for my $log (@$active_logs) {
			push @files, File::Tail->new( name => $log);
		}
		
		my $timeout = 60; #for now
		my ($nfound, $timeleft, @pending) = 
			File::Tail::select(undef, undef, undef, $timeout, @files);
		if ($nfound) {
			foreach my $file (@pending) {
				my $logfile = $file->{input};
				while (defined($line = $file->read)) {
					$self->process($logfile, $line);
				}
			}
		}
	}
}

sub scan_files {
	my ($self) = @_;
}

sub process {
	my ($self, $logfile, $text) = @_;

	
}


sub read_config {
	my ($self) = @_;

	if (defined $self->{cfg}) {
		if ($self->{cfg}->read() ) {
			$self->{cfg_reloaded} = 1;
			return $self->{cfg}->parse();
		}
	}
	return undef;
}

sub exit_loop {
	my ($self) = @_;

	return unless ($self && ref($self));
	$self->{keep_going} = 0;
}

sub log {
	my ($self, $log, $args) = @_;

	print STDERR "$log\n";
}

1;
