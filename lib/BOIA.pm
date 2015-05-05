package BOIA;
use strict;
use warnings;

use BOIA::Tail;
use IO::File;

use BOIA::Config;

our $version = '0.1';

sub new {
	my ($class, $arg) = @_;

	my $to_bless = $arg;
	$to_bless = {} if (ref($arg) eq 'HASH' || !$arg);

	my $self = bless $to_bless, ref($class) || $class;

	$self->{cfg} = BOIA::Config->new($arg);
	return undef unless $self->{cfg};

	# {ips}->{<ip>}->{ section => , unblock => , lastseen => {}, count => }

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

	my $tail = BOIA::Tail->new(@$active_logs);

	while ($self->{keep_going}) {
		if (defined $self->{cfg_reloaded}) {
			$self->{cfg_reloaded} = undef;
			$active_logs = $self->{cfg}->{active_sections};
			if (scalar( @{ $result->{errors} } ) || !scalar(@$active_logs) {
				$self->log_line($result->{errors});
				last;
			}
			$tail->set_files(@$active_logs);
		}
	
		my $timeout = 60; #for now
		while ($self->{keep_going} && !defined $self->{cfg_reloaded}) {
			my $pendings = $tail->tail($timeout);
			if ($pendings) {
				while ( my ($logfile, $fd) = each %$pendings ) {
					while (my $line = $fd->getline()) {
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
		ip	 => undef,
	);

	my $numfails = $self->{cfg}->get($logfile, 'numfails', 1);
	my $ipdef    = $self->{cfg}->get($logfile, 'ip');
	my $blockcmd = $self->{cfg}->get($logfile, 'blockcmd');

	my $regex  = $self->{cfg}->get($logfile, 'regex');
	for my $line (split /\n/, $text) {
		my @m = ( $text =~ /$regex/ );
		next unless scalar(@m);

		if ($ipdef) {
			$vars{ip} = $ipdef;
			$vars{ip} =~ s/(%(\d+))/ ($2<scalar(@m) && $2>0) ? $m[$2] : $1 /ge;

			my $ip = $vars{ip};

			# check against our hosts/IPs before continuing
			next if $self->{cfg}->is_my_host($ip);

			# TODO: decide where or not to call the blockcmd
			my $count = 0;
			if (defined $self->{ips}->{$ip}->{count}) {
				$count = $self->{ips}->{$ip}->{count};
			}
			if ($count < $numfails) {
				# we don't block the IP this time, but we remember it
				$self->{ips}->{$ip}->{count} = $count + 1;
				next;
			}
		}

		my $cmd = $blockcmd;
		
		$cmd =~ s/(%(\d+))/ ($2<scalar(@m) && $2>=0) ? $m[$2] : $1 /ge;		
		$cmd =~ s/(%([a-z]+))/ ( defined $vars{$2} ) ? $vars{$2} : $1 /ge;		

		# TODO: call blockcmd
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

sub log_line {
	my ($self, $log, $args) = @_;

	#for now we use STDERR, this is for test and debugging
	# TODO: switch to syslog for daemon mode
	print STDERR "$log\n";
}

1;
