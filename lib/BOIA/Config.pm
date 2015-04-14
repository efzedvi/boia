package BOIA::Config;
use warnings;
use strict;

use Config::Tiny;
use File::Path;
use File::Which;
use Net::CIDR::Lite;
use Net::CIDR;
use Socket;

use base qw(Class::Accessor);
__PACKAGE__->mk_ro_accessors(qw( active_sections file cfg ));


my $singleton;

sub new {
	my ($class, $arg) = @_;

	my $self = $singleton;
	if (!$self) {
		my $to_bless = {};
		my $file = $arg; 
		if (ref($arg) eq 'HASH') {
			$to_bless = $arg;
			$file = undef;
			$file = $arg->{file} if (defined $arg->{file});
		}

		$self = $singleton = bless $to_bless, ref($class) || $class;

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

		$self->{file} = $file;
		$self->{cfg} = undef;
		$self->{active_sections} = undef;
		$self->read();
	}

	return $self;
}

sub get {
	my ($self, $section, $var) = @_;

	return unless $var;

	$section = '_' unless $section;
	return undef unless (defined $self->{cfg});
	return undef unless (exists $self->{cfg}->{$section} && $self->{cfg}->{$section});
	return undef unless (exists $self->{cfg}->{$section}->{$var});

	return $self->{cfg}->{$section}->{$var};
}

sub read {
	my ($self) = @_;

	return unless (exists $self->{file} && $self->{file});
	$self->{cfg} = Config::Tiny->read($self->{file});
	return undef unless (defined $self->{cfg});

	# workdir is a special case
 	my $work_dir = $self->get(undef, 'workdir') || '/tmp/boia';
	if ($work_dir !~ /^\//) {
		my $home_dir = (getpwuid $>)[7];
		$work_dir = "$home_dir/".$work_dir;		
		$self->{cfg}->{_}->{workdir} = $work_dir
	}

	if ( ! -e $work_dir ) {
		mkpath($work_dir) || die "failed creating $work_dir directory";
	}

	if (defined $self->{cfg}->{_}->{myhosts}) {
		$self->{mynet} = $self->_process_myhosts($self->{cfg}->{_}->{myhosts});
	}

	return 1;
}

sub is_my_host {
	my ($self, $ip) = @_;

	return undef unless $ip;
	if (defined $self->{mynet}) {
		return $self->{mynet}->find($ip);
	}
	return 0;
}

sub get_sections {
	my ($self) = @_;

	return undef unless (defined $self->{cfg});

	my $sections = [ keys %{$self->{cfg}} ];
	return $sections;
}

# $errors is a arrayref, each element is an an error report line
sub parse {
	my ($self) = @_;

	return undef unless defined $self->{cfg};

	my $global_has_cmd = defined $self->get(undef, 'blockcmd');
	
	my $sections = [ keys %{$self->{cfg}} ];

	my $result = {
		active_sections => [],
		errors	=> []
	};

	for my $section (@$sections) {
		next if ($section eq '_');

		if (defined $self->{cfg}->{active} && 
		    ( $self->{cfg}->{active} eq 'false' || 
		      $self->{cfg}->{active} eq '0' || !$self->{cfg}->{active}) ) {
			push @{$result->{errors}}, "$section is not active";
			next;
		}

		if (!$section || ! -r $section) {
			push @{$result->{errors}}, "'$section' is not readable";
			next;
		}

		my $regex = $self->get($section, 'regex');

		if (!defined $regex) {
			push @{$result->{errors}}, "$section has no regex";
			next;
		}

		if ($regex) {
			eval { my $qr = qr/$regex/; };
			if ($@) {
				push @{$result->{errors}}, "$section has a bad regex: $@";
				next;
			}
		}

		my $blockcmd = $self->get($section, 'blockcmd');
		if (!defined $blockcmd && !$global_has_cmd) {
			push @{$result->{errors}}, "$section has no blockcmd";
			next;
		}
		
		for my $property ( qw( blockcmd blockstartcmd unblockcmd ) ) {
			my $cmd = $self->get($section, $property);
			if ($cmd) {
				my ($exe) = split(/\s/, $cmd);
				if ($exe !~ /^\//) {
					my $exe = which($exe);
				}
				if ( ! $exe || ! -x $exe ) {
					push @{$result->{errors}}, "$section doesn't have a proper $property";
				} 
			}
		}

		push @{$result->{active_sections}}, $section;
	}

	$self->{active_sections} = $result->{active_sections};

	return $result;
}

sub _process_myhosts {
	my ($class, $myhosts) = @_;

	return unless $myhosts;

	$myhosts =~ s/,/\ /g;
	
	my @hosts = split /\s+/, $myhosts;
	return unless scalar(@hosts);

	my $cidr = Net::CIDR::Lite->new;

	for my $host (@hosts) {
		if ($host =~ /[^\d\.-\/]/i) {
			my @addrs = gethostbyname($host);
			next unless scalar(@addrs);
			my @ips = map { inet_ntoa($_) } @addrs[4 .. $#addrs];
			next unless scalar(@ips);
			for my $ip (@ips) {
				eval { $cidr->add_any($ip); };
			}
		} else {
			eval { $cidr->add_any($host); };
		}
	}

	return $cidr;
}

1;
__END__
=head1 NAME

BOIA::Config - BOIA's config file reader, using Config::Tiny.

=head1 SYNOPSIS

	use BOIA::Config;

	my $cfg = BOIA::Config('/etc/boiarc');
	my $workdir = $cfg->get('workdir');
	# re-read
	$cfg->read();

=head1 DESCRIPTION

BOIA's config file reader, using Config::Tiny.

=head1 METHODS


=head2 new ($arg)

$arg can either be a hashref or an scalar value indicating a file name.
If no files provided it looks for ~/.boiarc, /etc/boiarc and 
/usr/local/etc/boiarc

=head2 get ( $section, $name )


=head2 read ()

=head2 get_sections()

=head2 process_myhosts($myhosts)

returns Net::CIDR::Lite object

=head2 is_my_host($ip)

return true or false

=head1 AUTHOR

Faraz Vahabzadeh C<< <faraz@fzv.ca> >>

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2013, Faraz Vahabzadeh.  All rights reserved.

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
