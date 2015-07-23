use Test::More tests => 9*2;
use warnings;
use strict;

use Test::Deep;
use File::Temp qw( :POSIX );
use File::Path;

use lib './lib';

use BOIA::Log;
use BOIA;


diag("--- Testing BOIA Filter");

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
blockcmd = echo global blockcmd %section %ip
unblockcmd = echo global unblockcmd %section %ip
zapcmd = echo global zap %section
startcmd = echo startcmd %section
filter= echo 

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
numfails = 2
unseen_period = 10m

EOF

my $cfg_file = tmpnam();
open FH, ">$cfg_file"; print FH $cfg_data; close FH;
unlink($jailfile);
my $b = BOIA->new($cfg_file);

my @tests = (
	{ #0
		section => 'logfile1',
		filter => 'echo 0 10.0.0.1',
		data   => "bad:1.2.3.0\n",
		jail   => {
			logfile1 => {
			}
		},
		logs   => [ 
			"Found offending 1.2.3.0 in logfile1",
			"filter returned 0, 10.0.0.1",
			"blocktime 0 whitelists 1.2.3.0",
		]
	},

	{ #1
		section => 'logfile1',
		filter => 'echo abc 10.0.0.1',
		data   => "bad:1.2.3.0\n",
		jail   => {
			logfile1 => {
				'1.2.3.0' => {
					'count' => 1,
					'lastseen' => $now,
				}
			}
		},
		logs   => [
			"Found offending 1.2.3.0 in logfile1",
			"filter returned abc, 10.0.0.1",
			"1.2.3.0 has been seen 1 times, not blocking yet"
		]
	},

	{ #2
		section => 'logfile1',
		filter => 'echo 10.0.0.1 10',
		data   => "bad:1.2.3.0\n",
		jail   => {
			logfile1 => {
				'1.2.3.0' => {
					'count' => 1,
					'lastseen' => $now,
				}
			}
		},
		logs   => [
			"Found offending 1.2.3.0 in logfile1",
			"filter returned 10.0.0.1, 10",
			"1.2.3.0 has been seen 1 times, not blocking yet"
		]
	},

	{ #3
		section => 'logfile1',
		filter => 'echo 5 10.0.0.1',
		data   => "bad:1.2.3.0\n",
		jail   => {
			logfile1 => {
				'1.2.3.0' => {
					'count' => 1,
					'lastseen' => $now,
					'release_time' => $now + 5,
					'blocktime' => 5,
					'ports' => { 22 => 1 },
				}
			}
		},
		logs   => [
			"Found offending 1.2.3.0 in logfile1",
			'filter returned 5, 10.0.0.1',
			"blocking 1.2.3.0 at logfile1 for 5 secs"
		]
	},

	{ #4
		section => 'logfile1',
		filter => 'echo 90 10.0.0.1/16',
		data   => "bad:1.2.3.0\n",
		jail   => {
			logfile1 => {
				'10.0.0.1/16' => {
					'count' => 1,
					'lastseen' => $now,
					'release_time' => $now + 90,
					'blocktime' => 90,
					'ports' => { 22 => 1 },
				}
			}
		},
		logs   => [
			"Found offending 1.2.3.0 in logfile1",
			'filter returned 90, 10.0.0.1/16',
			"blocking 10.0.0.1/16 at logfile1 for 90 secs",
		]
	},

	{ #5
		section => 'logfile1',
		filter => 'echo 9',
		data   => "bad:1.2.3.1\n",
		jail   => {
			logfile1 => {
				'1.2.3.1' => {
					'count' => 1,
					'lastseen' => $now,
					'release_time' => $now + 9,
					'blocktime' => 9,
					'ports' => { 22 => 1 },
				}
			}
		},
		logs   => [
			"Found offending 1.2.3.1 in logfile1",
			'filter returned 9, ',
			"blocking 1.2.3.1 at logfile1 for 9 secs"
		]
	},

	{ #6
		section => 'logfile1',
		filter => 'echo 9 something',
		data   => "bad:1.2.3.1\n1.2.3.3\n",
		jail   => {
			logfile1 => {
				'1.2.3.1' => {
					'count' => 1,
					'lastseen' => $now,
					'release_time' => $now + 9,
					'blocktime' => 9,
					'ports' => { 22 => 1 },
				}
			}
		},
		logs   => [
			"Found offending 1.2.3.1 in logfile1",
			'filter returned 9, something',
			"blocking 1.2.3.1 at logfile1 for 9 secs"
		]
	},

	{ #7
		section => 'logfile1',
		filter => 'echo xyz 10.0.0.1/16',
		data   => "bad:1.2.3.1\n1.2.3.3\n",
		jail   => {
			logfile1 => {
				'1.2.3.1' => {
					'count' => 1,
					'lastseen' => $now,
				}
			}
		},
		logs   => [
			"Found offending 1.2.3.1 in logfile1",
			'filter returned xyz, 10.0.0.1/16',
			'1.2.3.1 has been seen 1 times, not blocking yet', 
		]
	},
	{ #8
		section => 'logfile1',
		filter => 'echo 0 10.0.0.1/16',
		data   => "bad:1.2.3.1\n1.2.3.3\n",
		jail   => {
			logfile1 => {
			}
		},
		logs   => [
			  "Found offending 1.2.3.1 in logfile1",
			  "filter returned 0, 10.0.0.1/16",
			  "blocktime 0 whitelists 10.0.0.1/16"
		]
	},

	{
	},
);

#DBG
#use Data::Dumper;

my $bc = BOIA::Config->new();

my $i=0;
for my $test (@tests) {
	next unless %$test;
	$syslog = [];

	my $section = $test->{section};
	$bc->{cfg}->{$section}->{filter} = $test->{filter}; # change the filer
	$b->{jail} = {}; # flush the jail records

	$b->process($section, $test->{data});

#DBG
#	if ($i>0) {
#		print STDERR "$i\n";
#		print STDERR Dumper($b->{jail});
#		print STDERR Dumper($syslog);
#	}

	cmp_deeply($b->{jail}, $test->{jail}, "$i: Internal data stucture is good");
	cmp_bag($syslog, $test->{logs}, "$i: Logs are good");

	$i++;
}

unlink($jailfile);
unlink $cfg_file;
unlink $logfile1;
rmtree($workdir);

