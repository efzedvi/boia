package BOIA::Config;

use warnings;
use strict;

use Config::Tiny;
use File::Path;

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

		my @rcfiles = ( $ENV{HOME}.'/.boiarc', 
				'/etc/boiarc',
				'/usr/local/etc/boiarc' );

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
		$self->read();
	}

	return $self;
}

sub get {
	my ($self, $section, $var) = @_;

	return unless $var;

	$section = '_' unless $section;

	return unless (defined $self->{cfg});
	return unless (exists $self->{cfg}->{$section} && $self->{cfg}->{$section});
	return unless (exists $self->{cfg}->{$section}->{$var});

	return $self->{cfg}->{$section}->{$var};
}

sub read {
	my ($self) = @_;

	return unless (exists $self->{file} && $self->{file});
	$self->{cfg} = Config::Tiny->read($self->{file});

	# workdir is a special case
 	my $work_dir = $self->get(undef, 'workdir') || '/tmp/boia';
	if ($work_dir !~ /^\//) {
		my $home_dir = (getpwuid $>)[7];
		$self->{workdir} = "$home_dir/".$work_dir;		
	}

	if ( ! -e $self->get(undef, 'workdir') ) {
		mkpath($self->get(undef, 'workdir'));
	}

	return 1;
}

sub get_sections {
	my ($self) = @_;

	return unless (defined $self->{cfg});

	my $sections = [ keys %{$self->{cfg}}; ];
	return $sections;
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
