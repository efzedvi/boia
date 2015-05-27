package BOIA;
use strict;
use warnings;

use BOIA::Tail;
use IO::File;
use JSON;

use BOIA::Config;
use BOIA::Log;

our $VERSION = '0.1';

sub new {
	my ($class, $cfg_file) = @_;

	my $self = bless {}, ref($class) || $class;

	$self->{cfg} = BOIA::Config->new($cfg_file);
	return undef unless $self->{cfg};

	# {jail}->{<ip>}->{ section => { count => n, blocktime => t } }
	$self->{jail} = {};
	$self->load_jail();

	return $self;
}

sub version {
	return $VERSION;
}

sub nozap {
	my ($self, $nozap) = @_;
	
	if (defined $nozap) {
		$self->{nozap} = $nozap;
	}
	return $self->{nozap};
}

sub dryrun {
	my ($self, $flag) = @_;

	if (defined $flag) {
		$self->{dryrun} = $flag;
	}
	return $self->{dryrun};
}

sub run {
	my ($self, $is_daemon) = @_;

	if (!defined $self->{nozap}  || !$self->{nozap}) {
		$self->zap();
	}

	$self->{keep_going} = 1;

	my $result = $self->read_config();
	my $get_active_logs = BOIA::Config->get_active_sections();
	return undef if scalar( @{ $result->{errors} } ) || !scalar(@$get_active_logs);

	my $tail = BOIA::Tail->new(@$get_active_logs);

	while ($self->{keep_going}) {
		if (defined $self->{cfg_reloaded}) {
			$self->{cfg_reloaded} = undef;
			$get_active_logs = BOIA::Config->get_active_sections();
			if (scalar( @{ $result->{errors} } ) || !scalar(@$get_active_logs)) {
				for my $err (@{ $result->{errors} }) {
					BOIA::Log->write(LOG_ERR, $err);
				}
				last;
			}
		}
	
		my $timeout = 60; #for now
		while ($self->{keep_going} && !defined $self->{cfg_reloaded}) {
			# We set files every time to deal with log rotations
			$tail->set_files(@$get_active_logs); 
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

	my $get_active_sections = BOIA::Config->get_active_sections();
	for my $logfile (@$get_active_sections) {
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

	my $blocktime    = BOIA::Config->get($logfile, 'blocktime', 1800);
	my $release_time = time() + BOIA::Config->get($logfile, 'blocktime', 1800);
	my $vars = {
		section  => $logfile,
		protocol => BOIA::Config->get($logfile, 'protocol', ''),
		port	 => BOIA::Config->get($logfile, 'port', ''),
		blocktime => $blocktime,
		ip	 => undef,
	};

	my $numfails = BOIA::Config->get($logfile, 'numfails', 1);
	my $ipdef    = BOIA::Config->get($logfile, 'ip');
	my $blockcmd = BOIA::Config->get($logfile, 'blockcmd');

	my $regex  = BOIA::Config->get($logfile, 'regex');
	for my $line (split /\n/, $text) {
		my @m = ( $line =~ /$regex/ );
		next unless scalar(@m);

		my $ip;
		if ($ipdef) {
			$vars->{ip} = $ipdef;
			$vars->{ip} =~ s/(%(\d+))/ ($2<=scalar(@m) && $2>0) ? $m[$2-1] : $1 /ge;

			$ip = $vars->{ip};
			# check against our hosts/IPs before continuing
			if (BOIA::Config->is_my_host($ip)) {
				BOIA::Log->write(LOG_INFO, "$ip is in our network");
				next;
			}

			# decide where or not to call the blockcmd
			my $count = 0;
			if (defined $self->{jail}->{$ip}->{$logfile}->{count}) {
				$count = $self->{jail}->{$ip}->{$logfile}->{count};
			}
			$self->{jail}->{$ip}->{$logfile}->{count} = ++$count;
			if ($count < $numfails) {
				# we don't block the IP this time, but we remember it
				BOIA::Log->write(LOG_INFO, "$ip has been seen $count times, not blocking yet");
				next;
			}
		}

		my $cmd = $blockcmd;
		
		$cmd =~ s/(%(\d+))/ ($2<=scalar(@m) && $2>0) ? $m[$2-1] : $1 /ge;		

		# call blockcmd
		$self->run_cmd($cmd, $vars);
		if ($ip) {
			$self->{jail}->{$ip}->{$logfile}->{release_time} = $release_time;
			BOIA::Log->write(LOG_INFO, "blocking $ip");
		}
	}
	return 1;
}

sub release {
	my ($self) = @_;

	my $now = time();
	while ( my ($ip, $sections) = each %{ $self->{jail} } ) {
		while ( my ($section, $jail) = each %{ $sections } ) {
			next unless defined $jail->{release_time};
			if ($now > $jail->{release_time}) {
				my $unblockcmd = BOIA::Config->get($section, 'unblockcmd', '');
				next unless $unblockcmd;

				my $vars = {
					section  => $section,
					protocol => BOIA::Config->get($section, 'protocol', ''),
					port     => BOIA::Config->get($section, 'port', ''),
					blocktime => '',
					ip       => $ip,
				};

				$self->run_cmd($unblockcmd, $vars);
				delete $self->{jail}->{$ip}->{$section};
			}
		}
		# delete the ip in jail if we have already deleted all its records
		delete $self->{jail}->{$ip} unless scalar %{ $self->{jail}->{$ip} };	
	}

	$self->save_jail();
}

sub zap {
	my ($self) = @_;

	my $get_active_sections = BOIA::Config->get_active_sections();
	for my $section (@$get_active_sections) {
		my $zapcmd = BOIA::Config->get($section, 'zapcmd');
		next unless $zapcmd;

		my $vars = {
			section  => $section,
			protocol => BOIA::Config->get($section, 'protocol', ''),
			port     => BOIA::Config->get($section, 'port', ''),
			blocktime => '',
			ip       => '',
		};

		$self->run_cmd($zapcmd, $vars);
	}
	$self->{jail} = {};
	$self->save_jail();
}

sub read_config {
	my ($self) = @_;

	if (defined $self->{cfg}) {
		my $result = BOIA::Config->read();
		$self->{cfg_reloaded} = 1;
		#reset the flag if it's set
		$self->load_jail();
		$self->{saving_jail_failed} = undef if defined $self->{saving_jail_failed};
		return BOIA::Config->parse();
	}
	return undef;
}

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

	my $pid = fork();
	if (! defined $pid) {
		BOIA::Log->write(LOG_ERR, "fork() failed");
		die("fork() failed");
	} 

	return 1 if ($pid != 0);
	
	{ exec($cmd); }

	BOIA::Log->write(LOG_ERR, "Failed running cmd: $cmd");
	die("Failed running cmd: $cmd");
}

sub save_jail {
	my ($self) = @_;

	return undef unless defined $self->{jail};

	my $jail_file = BOIA::Config->get(undef, 'workdir')."/boia_jail";
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

	my $jail_file = BOIA::Config->get(undef, 'workdir')."/boia_jail";
	my $fd = IO::File->new($jail_file, 'r');
	if (!$fd) {
		BOIA::Log->write(LOG_ERR, "Failed reading jail file $jail_file");
		return undef;	
	}
	my $json_text;
	{ #slurp
		local $/;

		$json_text = <$fd>;
	}
	$fd->close();
	return unless $json_text;
	$self->{jail} = from_json $json_text;
	BOIA::Log->write(LOG_INFO, "Loaded jail file $jail_file");
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

=head2 run

=head2 nozap

=head2 dryrun

=head2 process

=head2 release

=head2 zap

=head2 read_config

=head2 exit_loop

=head2 save_jail

=head2 load_jail

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














