package BOIA;
use strict;
use warnings;

use BOIA::Tail;
use IO::File;

use BOIA::Config;
use BOIA::Log;

our $version = '0.1';

sub new {
	my ($class, $arg) = @_;

	my $to_bless = $arg;
	$to_bless = {} if (ref($arg) eq 'HASH' || !$arg);

	my $self = bless $to_bless, ref($class) || $class;

	$self->{cfg} = BOIA::Config->new($arg);
	return undef unless $self->{cfg};

	# {ips}->{<ip>}->{ sections =>[] , unblock => $,  count =>$ }
	$self->{ips} = {};

	return $self;
}

sub version {
	return $version;
}

sub run {
	my ($self, $is_daemon) = @_;

	my $log = BOIA::Log->new();

	if (!defined $self->{nozap}  || !$self->{nozap}) {
		$self->zap();
	}

	$self->{keep_going} = 1;

	my $result = $self->read_config();
	my $active_logs = $self->{cfg}->{active_sections};
	return undef if scalar( @{ $result->{errors} } ) || !scalar(@$active_logs);

	my $tail = BOIA::Tail->new(@$active_logs);

	while ($self->{keep_going}) {
		if (defined $self->{cfg_reloaded}) {
			$self->{cfg_reloaded} = undef;
			$active_logs = $self->{cfg}->{active_sections};
			if (scalar( @{ $result->{errors} } ) || !scalar(@$active_logs)) {
				for my $err (@{ $result->{errors} }) {
					$log->write(LOG_ERR, $err);
				}
				last;
			}
		}
	
		my $timeout = 60; #for now
		while ($self->{keep_going} && !defined $self->{cfg_reloaded}) {
			# We set files every time to deal with log rotations
			$tail->set_files(@$active_logs); 
			my $pendings = $tail->tail($timeout);
			if ($pendings) {
				while ( my ($logfile, $data) = each %$pendings ) {
					for my $line (split(/\n+/, $data)) {
						$self->process($logfile, $line);
					}
				}
			}
		}
	
		$self->release();
	}
}

sub scan_files {
	my ($self) = @_;

	my $active_sections = $self->{cfg}->{active_sections};
	for my $logfile (@$active_sections) {
		my $fd = IO::File->new($logfile);
		while (my $line = $fd->getline()) {
			$self->process($logfile, $line);
		}
	}
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

		my $ip;
		if ($ipdef) {
			$vars{ip} = $ipdef;
			$vars{ip} =~ s/(%(\d+))/ ($2<scalar(@m) && $2>0) ? $m[$2] : $1 /ge;

			$ip = $vars{ip};

			# check against our hosts/IPs before continuing
			next if $self->{cfg}->is_my_host($ip);

			# decide where or not to call the blockcmd
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

		# call blockcmd
		$self->run_cmd($cmd);
		if ($ip) {
			$self->{ips}->{$ip}->{unblock} = time() + $self->{cfg}->get($logfile, 'blocktime', 1800);
			push @{ $self->{ips}->{$ip}->{sections} }, $logfile;
		}
	}

}

sub release {
	my ($self) = @_;

	my $now = time();
	for my $ip (keys %{ $self->{ips}} ) {
		if ($now > $self->{ips}->{$ip}->{unblock} ) {
			for my $section ( @{ $self->{ips}->{$ip}->{sections} } ) {
				my $unblockcmd = $self->{cfg}->get($section, 'unblockcmd');
				$self->run_cmd($unblockcmd);
			}
			delete $self->{ips}->{$ip};
		}
	}
}

sub zap {
	my ($self) = @_;

	my $zapcmd = $self->{cfg}->get(undef, 'zapcmd');
	$self->run_cmd($zapcmd) if $zapcmd;

	my $active_sections = $self->{cfg}->{active_sections};
	for my $section (@$active_sections) {
		$zapcmd = $self->{cfg}->get($section, 'zapcmd');
		$self->run_cmd($zapcmd) if $zapcmd;
	}
	$self->{ips} = {};
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
	my ($self, @args) = @_;

	#for now we use STDERR, this is for test and debugging
	# TODO: switch to syslog for daemon mode
	print STDERR join(',', @args)."\n";
}


sub run_cmd {
	my ($self, $script) = @_;

	return unless $script;

	my $log = BOIA::Log->new();

	if (defined $self->{dryrun} && $self->{dryrun}) {
		$log->write(LOG_INFO, "dryrun: $script");
		return;
	}

	$log->write(LOG_INFO, "running: $script");

	my $pid = fork();
	if (! defined $pid) {
		$log->write(LOG_ERR, "fork() failed");
		die("fork() failed");
	} 

	return 1 if ($pid != 0);
	
	{ exec($script); }

	$log->write(LOG_ERR, "Failed running script: $script");
	die("Failed running script: $script");
}

1;
