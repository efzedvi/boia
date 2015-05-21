package BOIA::Log;


use base Exporter;

use warnings;
use strict;

use POSIX qw(strftime);
use Sys::Syslog qw(:standard :extended :macros);

our @EXPORT = qw(
	BOIA_LOG_SYSLOG
	BOIA_LOG_STDERR
);
our @EXPORT_OK = ( @EXPORT );
our %EXPORT_TAGS = ( 'all' => [ @EXPORT_OK ] );

use constant BOIA_LOG_SYSLOG => 1;
use constant BOIA_LOG_STDERR => 2;

my $singleton_ref;

sub new {
	my ($class, $level, $type) = @_;

	my $self = $singleton_ref;
	if (!$self) {
		$self = $singleton_ref = bless {}, ref($class) || $class;

		$self->set_options($level, $type);
		if ($type & BOIA_LOG_SYSLOG) {
			setlogsock 'native';
			openlog 'BOIA', 'nowait', LOG_SYSLOG;
			setlogmask(LOG_UPTO($level));
		}
	}

	return $self;
}

sub set_options {
	my ($self, $level, $type) = @_;

	$level ||= LOG_DEBUG;
	$type = BOIA_LOG_SYSLOG unless ( defined $type && 
					($type == BOIA_LOG_SYSLOG || $type == BOIA_LOG_STDERR || 
				 	$type == 0 || 
					$type == (BOIA_LOG_SYSLOG | BOIA_LOG_STDERR) ) );

	setlogmask(LOG_UPTO($level));
	$self->{type} = $type;
}

# just so that we can unit test it
sub write_stderr {
	my ($class, $timestamp, @stuff) = @_;

	if ($timestamp) {
		my $now_str = strftime("%Y-%m-%d,%H:%M:%S", localtime(time));
		print STDERR "$now_str: ";
	}
	print STDERR sprintf(@stuff)."\n";
}

# just so that we can unit test it
sub write_syslog {
	my ($class, $level, @stuff) = @_;

	syslog $level, sprintf(@stuff);
}

sub write {
	my ($self, $level, @stuff) = @_;

	return undef unless (defined $self->{type} && $self->{type});
	$level ||= LOG_INFO;

	if ($self->{type} & BOIA_LOG_SYSLOG) {
		$self->write_syslog($level, @stuff);
	}

	if ($self->{type} & BOIA_LOG_STDERR) {
		$self->write_stderr(1, @stuff);
	}
}

sub close {
	my ($self) = @_;

	closelog if ($self->{type} & BOIA_LOG_SYSLOG);
}
1;

__END__
=head1 NAME

BOIA::Log - BOIA's Log module

=head1 SYNOPSIS

	use BOIA::Log;

	my $log = BOIA::Log->new(SYSLOG | STDERR);
	$cfg->write(LOG_ERR, "an error happened");

=head1 DESCRIPTION

BOIA's logging mechanism, baiscally a wrapper around syslog

=head1 METHODS


=head2 new ($up_to_priority, $mechanism)


=head2 set_options ($up_to_priority, $mechanism)


=head2 write ( $priority, $logline )


=head2 close ()

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
