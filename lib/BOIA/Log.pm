package BOIA::Log;


use base Exporter;

use warnings;
use strict;

use IO::File;
use POSIX qw(strftime);
use Unix::Syslog qw(:subs :macros);

our @EXPORT = grep { $_ if /^LOG_/; } @Unix::Syslog::EXPORT_OK;

our @EXPORT_OK = ( @EXPORT );
our %EXPORT_TAGS = ( 'all' => [ @EXPORT_OK ] );

my $boia_log_singleton;

sub open {
	my ($class, $args) = @_;

	my $self = $boia_log_singleton;
	if (!$self) {
		my $to_bless = (ref($args) eq 'HASH') ? $args : {};
		$self = $boia_log_singleton = bless $to_bless, ref($class) || $class;	
	} elsif (ref($args) eq 'HASH') {
		while (my ($key, $val) = each (%$args)) {
			$self->{$key} = $val;
		}
	}

	my $level = LOG_DEBUG;
	if (defined($self->{level}) && $self->{level}) {
		$level = $self->{level};
	}
	$self->{level} = $level;

	if (defined($self->{syslog}) && $self->{syslog}) {
		#setlogsock 'native';
		openlog 'BOIA', LOG_CONS | LOG_NDELAY | LOG_NOWAIT, LOG_SYSLOG;
		setlogmask( $self->{level} );
	} else {
		closelog;
	}

	return $self;
}

# just so that we can unit test it
sub write_stderr {
	my ($class, $timestamp, $msg) = @_;

	if ($timestamp) {
		my $now_str = strftime("%Y-%m-%d,%H:%M:%S", localtime(time));
		print STDERR "$now_str: ";
	}
	print STDERR "$msg\n";
}

# just so that we can unit test it
sub write_syslog {
	my ($class, $level, $msg) = @_;

	syslog $level, $msg;
}


sub write_file {
        my ($self, $level, $msg) = @_;

	$self = $boia_log_singleton unless (ref($self) eq 'BOIA::Log');

        return unless ($msg && $level);

        return if $level > $self->{level};

        my $fh = IO::File->new(">>".$self->{file});
        if ($fh) {
		my $now_str = strftime("%Y-%m-%d,%H:%M:%S", localtime(time));
                print $fh "$now_str - $msg\n";
                $fh->close();
        }
}


sub write {
	my ($self, $level, $msg) = @_;

	$self = $boia_log_singleton unless (ref($self) eq 'BOIA::Log');

	$level ||= LOG_INFO;

	if (defined($self->{syslog}) && $self->{syslog}) {
		BOIA::Log->write_syslog($level, $msg);
	}

	if (defined($self->{stderr}) && $self->{stderr}) {
		BOIA::Log->write_stderr(0, $msg);
	}

	if (defined($self->{file}) && $self->{file}) {
		BOIA::Log->write_file($level, $msg);
	}
}

sub close {
	closelog;
}
1;

__END__
=head1 NAME

BOIA::Log - BOIA's Log module

=head1 SYNOPSIS

	use BOIA::Log;

	my $log = BOIA::Log->new({ level => LOG_INFO,
				   syslog => 1, 
				   stderr => 1, 
				   file => '/tmp/boia.log' });
	$cfg->write(LOG_ERR, "an error happened");

=head1 DESCRIPTION

BOIA's logging mechanism, baiscally a wrapper around syslog

=head1 METHODS


=head2 open ($up_to_priority, $mechanism)


=head2 set_options ($up_to_priority, $mechanism)


=head2 write ( $priority, $logline )


=head2 close ()


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
