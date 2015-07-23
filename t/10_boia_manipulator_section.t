use Test::More tests => 5*2;
use warnings;
use strict;

use Test::Deep;
use File::Temp qw( :POSIX );
use File::Path;

use lib './lib';

use BOIA::Log;
use BOIA;


diag("--- Testing BOIA's manipulator configuarion property ");

my $syslog = [];
my $now = 1000000;

no warnings 'redefine';
local *BOIA::Log::write_syslog = sub { my ($c, $l, $s) = @_; push @$syslog, $s };
local *BOIA::run_cmd = sub { 
	my ($c, $s, $v) = @_;
	
	my @a = split(/\s+/, $s);
	
	return [ 1, $a[1]."\n".$a[2], '' ] if scalar(@a) >=3;
	return [ 1, $a[1]."\n", '' ] if scalar(@a) < 3;
};
local *BOIA::_now = sub { $now; };
use warnings 'redefine';


BOIA::Log->open({ level => LOG_DEBUG, syslog => 1});

#-----------------------

my $workdir = tmpnam();
my $logfile1 = tmpnam()."1";

my $jailfile = "$workdir/boia_jail";

my $cfg_data = <<"EOF",
blockcmd = echo blockcmd %section %ip
unblockcmd = echo unblockcmd %section %ip

workdir = $workdir

myhosts = localhost 192.168.0.0/24
blocktime = 5m
numfails = 1

[logfile1]
logfile = $logfile1
port = 22
protocol = TCP 
regex = bad:([0-9]+\\\.[0-9]+\\\.[0-9]+\\\.[0-9]+)
ip=%1

blocktime = 1000s
numfails = 1
unseen_period = 10m

[passwd]
logfile = /etc/passwd
blocktime = 0
numfails = 2
regex = log:([0-9]+\\\.[0-9]+\\\.[0-9]+\\\.[0-9]+)
ip=%1
manipulator=true


EOF

my $cfg_file = tmpnam();
open FH, ">$cfg_file"; print FH $cfg_data; close FH;
unlink($jailfile);
my $b = BOIA->new($cfg_file);

my @tests = (
	{ #0
		section => 'logfile1',
		data   => "bad:1.2.3.0\nbad:1.2.3.0\n",
		jail   => {
			logfile1 => {
				'1.2.3.0' => {
					'ports' => { '22' => 1 },
					'count' => 2,
					'blocktime' => 1000,
					'lastseen' => 1000000,
					'release_time' => 1001000
				}
			}
		},
		logs   => [ 
			"Found offending 1.2.3.0 in logfile1",
			"blocking 1.2.3.0 at logfile1 for 1000 secs",
			"Found offending 1.2.3.0 in logfile1",
          		"1.2.3.0 has already been blocked (logfile1)",
		]
	},

	{ #1
		section => 'passwd',
		data   => "log:1.2.3.1\n",
		jail   => {
			logfile1 => {
				'1.2.3.0' => {
					'ports' => { '22' => 1 },
					'count' => 2,
					'blocktime' => 1000,
					'lastseen' => 1000000,
					'release_time' => 1001000
				}
			},
			'passwd' => {
			}
		},
		logs   => [
			'Found offending 1.2.3.1 in passwd',
			'blocktime 0 whitelists 1.2.3.1'
		]
	},

	{ #2
		section => 'passwd',
		data   => "log:1.2.3.0\n",
		filter => 'echo 0 1.2.3.0',
		jail   => {
			logfile1 => {
				'1.2.3.0' => {
					'ports' => { '22' => 1 },
					'count' => 2,
					'blocktime' => 1000,
					'lastseen' => 1000000,
					'release_time' => 1002000
				}
			},
			'passwd' => {
			}

		},
		logs   => [
			"Found offending 1.2.3.0 in passwd",
			'filter returned 0, 1.2.3.0',
			"1.2.3.0 at logfile1 jail time +1000 secs",
			"blocktime 0 whitelists 1.2.3.0"
		]
	},

	{ #3
		section => 'passwd',
		data   => "log:1.2.3.0\n",
		filter => 'echo 0 1.2.3.0/32',
		jail   => {
			logfile1 => {
				'1.2.3.0' => {
					'ports' => { '22' => 1 },
					'count' => 2,
					'blocktime' => 1000,
					'lastseen' => 1000000,
					'release_time' => 1003000
				}
			},
			'passwd' => {
			}

		},
		logs   => [
			"Found offending 1.2.3.0 in passwd",
			'filter returned 0, 1.2.3.0/32',
			"1.2.3.0/32 at logfile1 jail time +1000 secs",
			"blocktime 0 whitelists 1.2.3.0/32"
		]
	},

	{ #4
		section => 'passwd',
		data   => "log:1.2.3.0\n",
		jail   => {
			logfile1 => {
				'1.2.3.0' => {
					'ports' => { '22' => 1 },
					'count' => 2,
					'blocktime' => 1000,
					'lastseen' => 1000000,
					'release_time' => 1004000
				}
			},
			'passwd' => {
			}

		},
		logs   => [
			"Found offending 1.2.3.0 in passwd",
			"1.2.3.0 at logfile1 jail time +1000 secs",
			"blocktime 0 whitelists 1.2.3.0"
		]
	},

	{
	},
);

#use Data::Dumper;

my $bc = BOIA::Config->new();

my $i=0;
for my $test (@tests) {
	next unless %$test;
	$syslog = [];

	my $section = $test->{section};
	$bc->{cfg}->{$section}->{filter} = undef;
	$bc->{cfg}->{$section}->{filter} = $test->{filter} if defined $test->{filter};

	$b->process($section, $test->{data});

#	if ($i > 0) {
#		print STDERR "$i\n";
#		print STDERR Dumper($b->{jail});
#		print STDERR Dumper($syslog);
#	}

	cmp_deeply($b->{jail}, $test->{jail}, "$i: Internal data stucture is good");
	cmp_bag($syslog, $test->{logs}, "$i: Logs are good");

	$syslog = [];
	$i++;
}

unlink($jailfile);
unlink $cfg_file;
unlink $logfile1;
rmtree($workdir);

