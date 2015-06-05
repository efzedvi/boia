package BOIA::Config;
use warnings;
use strict;

use Config::Tiny;
use File::Path;
use File::Which;
use Net::CIDR::Lite;
use Net::CIDR;
use Sys::Hostname;
use Socket;


my $singleton;

sub new {
	my ($class, $file) = @_;

	my $self = $singleton;
	if (!$self) {
		my @rcfiles = ( $ENV{HOME}.'/.boia.conf', 
				'/etc/boia.conf',
				'/usr/local/etc/boia.conf' );

		if (! $file ) {
			$file = '';
			for my $rc (@rcfiles) {
				if ( -r $rc && -s $rc) {
					$file = $rc;
					last;
				}
			}
		}
		return undef unless ($file && -r $file);

		$self = $singleton = bless {}, ref($class) || $class;
		$self->{file} = $file;
		$self->{cfg} = undef;
		$self->{active_sections} = undef;
		$self->read();
	}

	return $self;
}

sub file {
	my ($self, $file) = @_;

	$self = $singleton unless (ref($self) eq 'BOIA::Config');
	if ($file && -r $file) {
		$self->{file} = $file;
	}
	return $self->{file};
}

sub get_active_sections {
	my ($self) = @_;

	$self = $singleton unless (ref($self) eq 'BOIA::Config');
	return $self->{active_sections};
}

sub get {
	my ($self, $section, $var, $default) = @_;

	return undef unless $var;
	$self = $singleton unless (ref($self) eq 'BOIA::Config');

	$section = '_' unless $section;
	return undef unless (defined $self->{cfg});
	return undef unless (exists $self->{cfg}->{$section} && $self->{cfg}->{$section});
	
	if (!defined $self->{cfg}->{$section}->{$var} && $section ne '_') {
		if (exists $self->{cfg}->{_}->{$var}) {
			return ($self->{cfg}->{_}->{$var} || $default);
		} else {
			return $default;
		}
	} 
		
	return $self->{cfg}->{$section}->{$var} || $default;
}

sub read {
	my ($self, $file) = @_;

	$self = $singleton unless (ref($self) eq 'BOIA::Config');
	$self->{file} = $file if $file && -r $file;

	return unless (exists $self->{file} && $self->{file});
	$self->{cfg} = Config::Tiny->read($self->{file});
	return undef unless (defined $self->{cfg});

	# workdir is a special case
 	my $work_dir = $self->get(undef, 'workdir') || '/tmp/boia';
	if ($work_dir !~ /^\//) {
		my $home_dir = (getpwuid $>)[7];
		$work_dir = "$home_dir/".$work_dir;		
	}
	$self->{cfg}->{_}->{workdir} = $work_dir;

	if ( ! -e $work_dir ) {
		mkpath($work_dir) || die "failed creating $work_dir directory";
	}

	if (defined $self->{cfg}->{_}->{myhosts}) {
		$self->process_myhosts();
	}

	return $self->parse();
}

sub is_my_host {
	my ($self, $ip) = @_;

	return undef unless $ip;
	$self = $singleton unless (ref($self) eq 'BOIA::Config');

	if (defined $self->{mynet}) {
		return $self->{mynet}->find($ip) ? 1 : 0;
	}
	return 0;
}

sub get_sections {
	my ($self) = @_;

	$self = $singleton unless (ref($self) eq 'BOIA::Config');
	return undef unless (defined $self->{cfg});

	my $sections = [ keys %{$self->{cfg}} ];
	return $sections;
}

# $errors is a arrayref, each element is an an error report line
sub parse {
	my ($self) = @_;

	$self = $singleton unless (ref($self) eq 'BOIA::Config');
	return undef unless defined $self->{cfg};

	my @global_params = qw/ blockcmd unblockcmd zapcmd myhosts blocktime numfails workdir unseen_period /;
	my @section_params = qw/ blockcmd unblockcmd zapcmd blocktime numfails active port protocol regex ip unseen_period /;

	my %valid_global_params  = map { $_ => 1; } @global_params;
	my %valid_section_params = map { $_ => 1; } @section_params;

	my $result = {
		active_sections => [],
		errors	=> []
	};

	foreach my $param ( keys %{ $self->{cfg}->{_}  } ) {
		if (!exists $valid_global_params{$param}) {
			push @{$result->{errors}}, "Invalid parameter '$param' in global section";
		}
	}

	my $global_has_cmd = $self->verify_cmd($self->get(undef, 'blockcmd'));
	if (!defined $global_has_cmd) {
		push @{$result->{errors}}, "Global section has an invalid blockcmd";
	}

	for my $property ( qw( unblockcmd zapcmd ) ) {
		if (!defined($self->verify_cmd($self->get(undef, $property)))) {
			push @{$result->{errors}}, "Global section has an invalid $property";
		}
	}

	for my $property ( qw( blocktime unseen_period ) ) {
		my $time_str = $self->get('_', $property);
		if (defined $time_str) {
			my $seconds = $self->parse_time($time_str);
			if (!$seconds || $seconds < 0) {
				push @{$result->{errors}}, "Global section has an invalid $property";
				next;
			} 
			$self->{cfg}->{_}->{$property} = $seconds;
		} 
	}

	# numeric check
	for my $property ( qw/ numfails /) {
		my $val = $self->get('_', $property);
		if ($val && $val !~ m/^\d+$/) {
			push @{$result->{errors}}, "$property in Global must be numeric";
		}
	}

	for my $section ( keys %{$self->{cfg}} ) {
		next if ($section eq '_');

		foreach my $param ( keys %{ $self->{cfg}->{$section}  } ) {
			if (!exists $valid_section_params{$param}) {
				push @{$result->{errors}}, "Invalid parameter '$param' in $section section";
			}
		}

		my $active = $self->get($section, 'active');
		next if (defined($active) && ($active eq '0' || $active eq 'false'));

		if (!$section || ! -r $section) {
			push @{$result->{errors}}, "'$section' is not readable";
		}

		my $regex = $self->get($section, 'regex');
		if (!defined $regex) {
			push @{$result->{errors}}, "$section has no regex";
		}

		if ($regex) {
			eval { my $qr = qr/$regex/; };
			if ($@) {
				push @{$result->{errors}}, "$section has a bad regex";
			}
		}

		my $has_blockcmd = 1;
		my $blockcmd = $self->get($section, 'blockcmd');
		if (!defined $blockcmd && !$global_has_cmd) {
			push @{$result->{errors}}, "$section has no blockcmd";
			$has_blockcmd = 0;
		}

		for my $property ( qw( blockcmd unblockcmd zapcmd ) ) {
			if (!$self->verify_cmd($self->get($section, $property))) {
				push @{$result->{errors}}, "$section does not have a proper $property";
			}
		}

		for my $property ( qw( blocktime unseen_period ) ) {
			my $time_str = $self->get($section, $property);
			if (defined $time_str) {
				my $seconds = $self->parse_time($time_str);
				if (!$seconds || $seconds < 0) {
					push @{$result->{errors}}, "$section has an invalid $property";
					next;
				} 
				$self->{cfg}->{$section}->{$property} = $seconds;
			} 
		}

		for my $property ( qw/ numfails /) {
			my $val = $self->get($section, $property);
			if ($val && $val !~ m/^\d+$/) {
				push @{$result->{errors}}, "$property in $section section must be numeric";
			}
		}

		push @{$result->{active_sections}}, $section if $has_blockcmd;
	}

	$self->{active_sections} = $result->{active_sections};

	return $result;
}

sub process_myhosts {
	my ($self, $myhosts) = @_;

	$self = $singleton unless (ref($self) eq 'BOIA::Config');
	$myhosts ||= $self->{cfg}->{_}->{myhosts};
	$myhosts .= " 127.0.0.1/24 ".hostname(); # make sure we never block ourselves

	$myhosts =~ s/,/\ /g;
	
	my @hosts = split /\s+/, $myhosts;
	return unless scalar(@hosts);

	my $cidr = Net::CIDR::Lite->new;

	for my $host (@hosts) {
		$host = lc $host;
		if ($host =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(\/\d{1,3})?$/) {
			eval { $cidr->add_any($host); };
		} elsif ($host =~ /[a-z\.]+/) {
			my @addrs = gethostbyname($host);
			next unless scalar(@addrs);
			my @ips = map { inet_ntoa($_) } @addrs[4 .. $#addrs];
			next unless scalar(@ips);
			for my $ip (@ips) {
				eval { $cidr->add_any($ip); };
			}
		}
	}

	$self->{mynet} = $cidr;
	return $cidr;
}

sub parse_time {
	my ($class, $str) = @_;

	return unless $str;

	my %uc = ( d => 24*3600, h => 3600, m => 60, s => 1 );

	if ($str =~ /^(\d+)([dhms]?)$/) {
		my $n = $1;
		my $u = 1;
		$u = $uc{$2} if (defined($2) && exists $uc{$2});
		return $n*$u;
	}
	return undef;
}

sub verify_cmd {
	my ($class, $string) = @_;

	return 0 unless $string;

	$string =~ s/^\s+//; # ltrim

	my ($cmd) = split(/\s/, $string);

	return 0 unless $cmd;

	if ($cmd !~ /^\//) {
		$cmd = which($cmd);
	}
	if ( ! $cmd || ! -x $cmd ) {
		return undef;
	}
	return 1;
}

1;
__END__
=head1 NAME

BOIA::Config - BOIA's config file reader, using Config::Tiny.

=head1 SYNOPSIS

	use BOIA::Config;

	my $cfg = BOIA::Config->new('/etc/boia.conf');
	my $workdir = $cfg->get(undef, 'workdir');
	# re-read
	$cfg->read();

=head1 DESCRIPTION

BOIA's config file reader, using Config::Tiny.

=head1 METHODS

=head2 new ($cfg_file)

$cfg_file is the config file, if not present then it looks for 
~/.boia.conf, /etc/boia.conf and /usr/local/etc/boia.conf
This module/class is a singleton.

=head2 get ( $section, $name, $default_value)

Returns paramter specified by $name, from $section. If $section is undef
then the default/global section is used. If there are no $name under
$section, it tries to find the same paramter under global/default, if that
failes too then $default_value is returned.

=head2 read ()

Reads and parses the config file, return value is the same as the one of parse().

=head2 parse ()

Parses the config file and tries to find as many as problems that it can.
The return value is a hashref, of two keys. 'errors' is an arrayref of
all the errors, and 'active_sections' lists the active sections found.

=head2 file($file)

Gets/sets the config file.

=head2 get_sections()

Returns an arrayref of active sections.

=head2 process_myhosts()

Processes the myhosts paramter and returns a CIDR object

=head2 is_my_host($ip)

Return true or false depending on whether $ip is a member of 'myhosts' or not.

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
