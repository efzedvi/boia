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
		while ($self->{keep_going} && !defined $self->{cfg_reloaded}) {
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
}

sub scan_files {
	my ($self) = @_;
}

sub process {
	my ($self, $logfile, $text) = @_;

	return undef unless $logfile && $text;

	my %vars = (
		section  => $logfile,
		protocol => $self->{cfg}->get($logfile, 'protocol'),
		port	 => $self->{cfg}->get($logfile, 'port'),
		timestamp=> time(),
		ip	 => undef
	);

	my $ipdef = $self->{cfg}->get($logfile, 'ip');

	my $regex  = $self->{cfg}->get($logfile, 'regex');
	for my $line (split /\n/, $text) {
		my @m = ( $text =~ /$regex/ );
		next unless scalar(@m);

		if ($ipdef) {
			$vars{ip} = $ipdef;
			$vars{ip} =~ s/(%(\d+))/ ($2<=scalar(@m) && $2>0) ? $m[$2-1] : $1 /ge;
		}
		
		my $cmd = $self->{cfg}->get($logfile, 'blockcmd') ||
			  $self->{cfg}->get(undef, 'blockcmd');
		
		$cmd =~ s/(%(\d+))/ ($2<=scalar(@m) && $2>0) ? $m[$2-1] : $1 /ge;		
		$cmd =~ s/(%([a-z]+))/ ( defined $vars{$2} ) ? $vars{$2} : $1 /ge;		

		# found a match	
		# TODO: ...
	}

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

	#for now we use STDERR, this is for test and debugging
	# TODO: switch to syslog for daemon mode
	print STDERR "$log\n";
}

1;
