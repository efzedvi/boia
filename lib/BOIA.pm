package BOIA;
use strict;
use warnings;

use BOIA::Tail;
use IO::File;
use IPC::Cmd qw( can_run run run_forked );
use JSON;

use BOIA::Config;
use BOIA::Log;

our $VERSION = '0.1';

use constant {
	UNSEEN_PERIOD	=> 3600,
	TAIL_TIMEOUT	=> 30,
	BLOCKTIME	=> 3600,
	CMD_TIMEOUT  	=> 30,
};

sub new {
	my ($class, $cfg_file) = @_;

	my $self = bless {}, ref($class) || $class;

	$self->{cfg} = BOIA::Config->new($cfg_file);
	return undef unless $self->{cfg};

	# {jail}->{<$logfile>}->{ ip => { count => n, release_time => t } ... }
	$self->{jail} = {};

	return $self;
}

sub version {
	return $VERSION;
}

# just so that we can redifine it in unit tests
sub _now {
	return time();
}

sub dryrun {
	my ($self, $flag) = @_;

	if (defined $flag) {
		$self->{dryrun} = $flag;
	}
	return $self->{dryrun};
}

sub read_config {
	my ($self) = @_;

	my $result = BOIA::Config->read();
	my $active_logs = BOIA::Config->get_active_sections();
	if (scalar( @{ $result->{errors} } ) || !scalar(@$active_logs)) {
		for my $err (@{ $result->{errors} }) {
			BOIA::Log->write(LOG_ERR, $err);
		}
		if (!scalar(@$active_logs)) {
			BOIA::Log->write(LOG_ERR, "No active sections found");
		}
	}
	return $result;
}

sub loop {
	my ($self) = @_;

	$self->{keep_going} = 1;

	my $result = $self->read_config();
	my $active_logs = BOIA::Config->get_active_sections();
	return undef if (scalar( @{ $result->{errors} } ) || !scalar(@$active_logs));
	$self->start();
	$self->load_jail();

	my $tail = BOIA::Tail->new(@$active_logs);

	while ($self->{keep_going}) {
		if (defined $self->{cfg_reloaded}) {
			$self->{cfg_reloaded} = undef;
			$result = $self->read_config();
			$active_logs = BOIA::Config->get_active_sections();
			return undef if scalar( @{ $result->{errors} } ) || !scalar(@$active_logs);
			$self->start();
			$self->load_jail();
		}

		my $timeout = TAIL_TIMEOUT; #for now
		while ($self->{keep_going} && !defined $self->{cfg_reloaded}) {
			# keep running process_myhosts() just in case some have short TTLs 
			BOIA::Config->process_myhosts();
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
			$self->release();
		}
	}
}

sub scan_files {
	my ($self) = @_;

	$self->start();
	$self->load_jail();
	my $active_sections = BOIA::Config->get_active_sections();
	for my $logfile (@$active_sections) {
		my $fd = IO::File->new($logfile);
		while (my $line = $fd->getline()) {
			$self->process($logfile, $line);
		}
	}
	$self->release();
}

sub process {
	my ($self, $logfile, $text) = @_;

	return undef unless $logfile && $text;

	my $blocktime = BOIA::Config->get($logfile, 'blocktime', BLOCKTIME);
	my $numfails = BOIA::Config->get($logfile, 'numfails', 1);
	my $ipdef    = BOIA::Config->get($logfile, 'ip', '');
	my $portdef  = BOIA::Config->get($logfile, 'port', '');
	my $blockcmd = BOIA::Config->get($logfile, 'blockcmd');
	my $regex  = BOIA::Config->get($logfile, 'regex');
	my $filter = BOIA::Config->get($logfile, 'filter');

	my $vars = {
		section  => $logfile,
		protocol => BOIA::Config->get($logfile, 'protocol', ''),
		port	 => $portdef,
		name	 => BOIA::Config->get($logfile, 'name', ''),
		blocktime => $blocktime,
		count    => 0,
		ip	 => $ipdef,
	};

	if (!$regex) {
		BOIA::Log->write(LOG_ERR, "$logfile missing regex");
		return;
	}

	if (!$blockcmd) {
		BOIA::Log->write(LOG_ERR, "$logfile missing blockcmd");
		return;
	}

	for my $line (split /\n/, $text) {
		my @m = ( $line =~ /$regex/ );
		next unless scalar(@m);

		$vars->{ip} = $ipdef;
		$vars->{port} = $portdef;
		if ($ipdef) {
			my $ip;
			my $_ip = $ipdef;
			$_ip =~ s/(%(\d+))/ ($2<=scalar(@m) && $2>0) ? $m[$2-1] : $1 /ge;
			$ip = $_ip if BOIA::Config->is_ip($_ip);
			$vars->{port} =~ s/(%(\d+))/ ($2<=scalar(@m) && $2>0) ? $m[$2-1] : $1 /ge;

			if ($ip) {
				BOIA::Log->write(LOG_INFO, "Found offending $ip in $logfile");

				# check against our hosts/IPs before continuing
				if (BOIA::Config->is_my_host($ip)) {
					BOIA::Log->write(LOG_INFO, "$ip is in our network");
					next;
				}

				# decide where or not to call the blockcmd
				my $count = 0;
				if (defined $self->{jail}->{$logfile}->{$ip}->{count}) {
					$count = $self->{jail}->{$logfile}->{$ip}->{count};
				} else {
					# clean up after the auto-vivification 
					delete $self->{jail}->{$logfile}->{$ip};
				}

				$vars->{count} = $count;

				# prepare to run the filter if it exists
				$vars->{ip} = $ip;
				my $bt = $blocktime;
				my $filter_ran = 0;
				if ($filter) {
					my $cmd = $filter;
					$cmd =~ s/(%(\d+))/ ($2<=scalar(@m) && $2>0) ? $m[$2-1] : $1 /ge;
					my $rv = $self->run_cmd($cmd, $vars);
					my ($ok, $out, $err);
					($ok, $out, $err) = @$rv if ($rv && ref($rv) eq 'ARRAY');
					if ($ok) {
						# get the first two lines
						my ($line0, $line1) = split(/\n/, $out);
						$line0 = defined($line0) ? $line0 : ''; 
						$line1 = defined($line1) ? $line1 : ''; 
						BOIA::Log->write(LOG_INFO, "filter returned $line0, $line1");
						# sanity check the filter output
						#filter only comes to play when $line0(or $bt) > 0
						if ($line0 =~ /^\d+$/) {
							$filter_ran = 1;
							$bt = $line0;
							if (BOIA::Config->is_net($line1)) {
								$vars->{ip} = $ip = $line1;
							}
						}
					}
				}

				if (BOIA::Config->get($logfile, 'manipulator')) {
					$self->add_blocktime_to_all($ip, $logfile);
				}

				if (!$bt) {
					BOIA::Log->write(LOG_INFO, "blocktime 0 whitelists $ip");
					next;
				}

				$self->{jail}->{$logfile}->{$ip}->{lastseen} = $self->_now();
				$self->{jail}->{$logfile}->{$ip}->{count} = ++$count;

				if ($count < $numfails && !$filter_ran ) {
					# we don't block the IP this time, but we remember it
					BOIA::Log->write(LOG_INFO, "$ip has been seen $count times, not blocking yet");
					next;
				}

				# add the port to the list of ports that this $ip has attempted to connect to
				if ($portdef) {
					my $ports = {};
					if (exists $self->{jail}->{$logfile}->{$ip}->{ports}) {
						$ports = $self->{jail}->{$logfile}->{$ip}->{ports};
					}
					
					if (exists $ports->{ $vars->{port} } &&
					    defined $self->{jail}->{$logfile}->{$ip}->{release_time}) {
						# Deja vu, we have seen this IP, ignore, so scan_files() wouldn't mess up
						BOIA::Log->write(LOG_INFO, "$ip has already been blocked ($logfile)");
						next;
					}
					
					$ports->{$vars->{port}}++;
					$self->{jail}->{$logfile}->{$ip}->{ports} = $ports;
				} else {
					if (defined $self->{jail}->{$logfile}->{$ip}->{release_time}) {
						# Deja vu, we have seen this IP, ignore, so scan_files() wouldn't mess up
						BOIA::Log->write(LOG_INFO, "$ip has already been blocked ($logfile)");
						next;
					}
				}

				# now we can jail the $ip
				$self->{jail}->{$logfile}->{$ip}->{release_time} = $self->_now() + $bt;
				$self->{jail}->{$logfile}->{$ip}->{blocktime} = $bt;

				BOIA::Log->write(LOG_INFO, "blocking $ip at $logfile for $bt secs");
			}
		}
		my $cmd = $blockcmd;
		$cmd =~ s/(%(\d+))/ ($2<=scalar(@m) && $2>0) ? $m[$2-1] : $1 /ge;		

		# call blockcmd
		$self->run_cmd($cmd, $vars);
	}
	return 1;
}

sub release {
	my ($self) = @_;

	my $now = $self->_now();
	while ( my ($section, $ips) = each %{ $self->{jail} } ) {
		while ( my ($ip, $jail) = each %{ $ips } ) {
			my $unseen_period = BOIA::Config->get($section, 'unseen_period', UNSEEN_PERIOD);
			if (! defined($jail->{release_time}) ) { # not in jail
				if ($jail->{lastseen} + $unseen_period <= $self->_now()) {
					# forget it if not in jail and unseen for UNSEEN_TIME time
					delete $self->{jail}->{$section}->{$ip};
				}
			} elsif ($now > $jail->{release_time}) { # in jail
				my $unblockcmd = BOIA::Config->get($section, 'unblockcmd', '');
				next unless $unblockcmd;

				my $vars = {
					section  => $section,
					protocol => BOIA::Config->get($section, 'protocol', ''),
					port     => BOIA::Config->get($section, 'port', ''),
					name	 => BOIA::Config->get($section, 'name', ''),
					blocktime => '',
					count	 => '',
					ip       => $ip,
				};
			
				BOIA::Log->write(LOG_INFO, "unblocking $ip for $section");

				my @ports = ();
				if (exists $self->{jail}->{$section}->{$ip}->{ports} ) {
					for my $port ( keys %{ $self->{jail}->{$section}->{$ip}->{ports} } ) {
						$vars->{port} = $port;
						$self->run_cmd($unblockcmd, $vars);
					}
				} else { 
					$self->run_cmd($unblockcmd, $vars);
				}

				delete $self->{jail}->{$section}->{$ip};
			}
		}
		# delete the ip in jail if we have already deleted all its records
		delete $self->{jail}->{$section} unless scalar %{ $self->{jail}->{$section} };	
	}

	$self->save_jail();
}

sub zap {
	my ($self, @sections) = @_;

	my $active_sections = BOIA::Config->get_active_sections();
	my %active_section_hash = map { $_ => 1; } @$active_sections;
	if (scalar(@sections) == 0) {
		@sections = @$active_sections;
	}

	for my $section (@sections) {
		next unless exists $active_section_hash{$section};

		my $zapcmd = BOIA::Config->get($section, 'zapcmd');

		my $vars = {
			section  => $section,
			protocol => BOIA::Config->get($section, 'protocol', ''),
			port     => BOIA::Config->get($section, 'port', ''),
			name	 => BOIA::Config->get($section, 'name', ''),
			blocktime => '',
			count	 => '',
			ip       => '',
		};

		if ($zapcmd) {
			$self->run_cmd($zapcmd, $vars);
		} else {
			#if no zapcmd then unblock every darn IP of the $section
			my $unblockcmd = BOIA::Config->get($section, 'unblockcmd');
			next unless $unblockcmd;

			while (my ($ip, $jail) = each ( %{ $self->{jail}->{$section} } ) ) {
				$vars->{ip} = $ip;
				$self->run_cmd($unblockcmd, $vars);
			}
		}
		delete $self->{jail}->{$section};
	}
	$self->{jail} = {} unless scalar %{ $self->{jail} };

	$self->save_jail();
}

sub start {
	my ($self, @sections) = @_;

	my $active_sections = BOIA::Config->get_active_sections();
	my %active_section_hash = map { $_ => 1; } @$active_sections;
	if (scalar(@sections) == 0) {
		@sections = @$active_sections;
	}

	for my $section (@sections) {
		next unless exists $active_section_hash{$section};

		my $startcmd = BOIA::Config->get($section, 'startcmd');

		my $vars = {
			section  => $section,
			protocol => BOIA::Config->get($section, 'protocol', ''),
			port     => BOIA::Config->get($section, 'port', ''),
			name	 => BOIA::Config->get($section, 'name', ''),
			blocktime => '',
			count	 => '',
			ip       => '',
		};

		if ($startcmd) {
			$self->run_cmd($startcmd, $vars);
		}
	}
}

# called by sig HUP
sub reload_config {
	my ($self) = @_;

	my $rc = 0;
	if (defined $self->{cfg}) {
		$self->{cfg_reloaded} = 1;
		#reset the flag if it's set
		$self->{saving_jail_failed} = undef if defined $self->{saving_jail_failed};
		BOIA::Log->write(LOG_INFO, "Reread the config file: ".BOIA::Config->file);
		$rc = 1;
	}
	return $rc;
}

# called by sig INT 
sub exit_loop {
	my ($self) = @_;

	return unless ($self && ref($self));
	$self->{keep_going} = 0;
}

sub run_cmd {
	my ($self, $cmd, $vars) = @_;

	return unless $cmd;
	$vars ||= {};

	$cmd =~ s/(%([a-z]+))/ ( defined $vars->{$2} ) ? $vars->{$2} : $1 /ge;

	if (defined $self->{dryrun} && $self->{dryrun}) {
		BOIA::Log->write(LOG_INFO, "dryrun: $cmd");
		return;
	}

	BOIA::Log->write(LOG_INFO, "running: $cmd");

	my ($success, $stdout, $stderr, $rc) = (1, '', '');
	$IPC::Cmd::VERBOSE = 0;
	if (IPC::Cmd->can_use_run_forked) {
		my $result = run_forked($cmd, { timeout => CMD_TIMEOUT });
		$stderr = $result->{stderr};
		$stdout = $result->{stdout};
		if ($result->{exit_code} != 0 || $result->{timeout}) {
			$success = 0;
			$rc = $result->{err_msg};
		}
	} else {
		my( $_success, $error_msg, $full_buf, $stdout_buf, $stderr_buf ) =
        		run( command => $cmd, verbose => 0, timeout => CMD_TIMEOUT );
		$stderr = join '', @$stderr_buf;
		$stdout = join '', @$stdout_buf;
		if (!$_success) {
			$success = 0;
			$rc = $error_msg;
		}
	}

	if (!$success) {
		BOIA::Log->write(LOG_ERR, "Failed running cmd: $cmd with : rc=$rc".
			 	 " stderr=$stderr");
	}

	return [ $success, $stdout, $stderr ];
}

sub save_jail {
	my ($self) = @_;

	return undef unless defined $self->{jail};

	my $jail_file = BOIA::Config->get(undef, 'workdir', '/tmp')."/boia_jail";
	my $fd = IO::File->new($jail_file, 'w');
	if (!$fd) {
		if (!defined $self->{saving_jail_failed}) {
			BOIA::Log->write(LOG_ERR, "Failed saving jail file $jail_file");
			$self->{saving_jail_failed} = 1;
		}
		return undef;	
	}
	my $json_text = to_json($self->{jail}, { ascii => 1, pretty => 1 } );
	print $fd $json_text;
	$fd->close();
	$self->{saving_jail_failed} = undef if defined $self->{saving_jail_failed};
}

sub load_jail {
	my ($self) = @_;

	my $jail_file = BOIA::Config->get(undef, 'workdir', '/tmp')."/boia_jail";
	my $fd = IO::File->new($jail_file, 'r');
	if (!$fd) {
		BOIA::Log->write(LOG_INFO, "Failed reading jail file $jail_file");
		return undef;	
	}
	my $json_text;
	{ #slurp
		local $/;

		$json_text = <$fd>;
	}
	$fd->close();
	return unless $json_text;
	my $href = from_json $json_text;
	if (!$href || ref($href) ne 'HASH') {
		BOIA::Log->write(LOG_INFO, "Failed reading jail file $jail_file, bad format");
		return undef;
	}
	$self->{jail} = $href;
	#BOIA::Log->write(LOG_INFO, "Loaded jail file $jail_file");
}

sub list_jail {
	my ($self) = @_;

	my $list = [];
	while ( my ($section, $ips) = each %{ $self->{jail} } ) {
		while ( my ($ip, $jail) = each %{ $ips } ) {
			next unless (defined $jail->{release_time} && defined $jail->{count});

			push @$list, [ $ip, $section, $jail->{count}, $jail->{release_time} ];
		}
	}

	return $list;
}

sub add_blocktime_to_all {
	my ($self, $ip, $exclude_section) = @_;

	while ( my ($section, $ips) = each %{ $self->{jail} } ) {
		next if ($exclude_section && $section eq $exclude_section);
		while ( my ($jailed_ip, $jail) = each %{ $ips } ) {
			next unless defined $jail->{release_time};

			if ($self->same_ip($ip, $jailed_ip)) {
				$jail->{release_time} += $jail->{blocktime};
				BOIA::Log->write(LOG_INFO, 
		 				 sprintf("%s at %s jail time +%d secs",
			 				 $ip, $section, $jail->{blocktime}));
			}
		}
	}
}

sub same_ip {
        my ($class, $ip1, $ip2) = @_;

        return 1 if $ip1 eq $ip2;
        $ip1 =~ s/\/(32|128)//;
        $ip2 =~ s/\/(32|128)//;
        return 1 if $ip1 eq $ip2;
        return 0;
}



1;
__END__
=head1 NAME

BOIA - Block Offending IP Addresses 

=head1 SYNOPSIS

	use BOIA::Config;

	my $boia = BOIA->new();
	$boia->scan_files();
	# or 
	$boia->run();

=head1 DESCRIPTION

This module does the core functionality of BOIA.

=head1 METHODS

=head2 new ($cfg_file)

$cfg_file is the config file, if not present then it looks for 
~/.boia.conf, /etc/boia.conf and /usr/local/etc/boia.conf

=head2 version

=head2 scan_files

=head2 loop

=head2 nozap

=head2 dryrun

=head2 process

=head2 release

=head2 zap

=head2 start

=head2 read_config

=head2 reload_config

=head2 exit_loop

=head2 save_jail

=head2 load_jail

=head2 list_jail

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


