use Test::More tests => 6+4*3+1+3+1+2+4;
use warnings;
use strict;

use Test::Deep;
use File::Temp qw( :POSIX );
use File::Path;

use lib './lib';

use BOIA::Log;
use BOIA;

diag("--- Testing BOIA");

my $syslog = [];

no warnings 'redefine';
local *BOIA::Log::write_syslog = sub { my ($c, $l, $s) = @_; push @$syslog, $s };
use warnings 'redefine';

BOIA::Log->open({ level => LOG_DEBUG, syslog => 1});

#-----------------------
ok(!defined BOIA->new(), "new() failed as expected");
ok(!defined BOIA->new('/dev/something'), "new() failed as expected again");

my $workdir = tmpnam();
my $logfile1 = tmpnam()."1";
my $logfile2 = tmpnam()."2";
my $logfile3 = tmpnam()."3";

my $jailfile = "$workdir/boia_jail";

open FH, ">$logfile1"; print FH "data\n"; close FH;
open FH, ">$logfile2"; print FH "data\n"; close FH;
open FH, ">$logfile3"; print FH "data3\ndata4\n"; close FH;

my $cfg_data = <<"EOF",
blockcmd = echo global blockcmd %section %ip
unblockcmd = echo global unblockcmd %section %ip
zapcmd = echo global zap %section

workdir = $workdir

myhosts = localhost 192.168.0.0/24
blocktime = 5m
numfails = 1

[$logfile1]
port = 22
protocol = TCP 
regex = ([0-9]+\\\.[0-9]+\\\.[0-9]+\\\.[0-9]+) on 
ip=%1
blockcmd = echo %section %protocol %port %ip %blocktime
unblockcmd = echo unblock %section %ip
zapcmd = echo zap %section

blocktime = 1000s
numfails = 2
unseen_period = 10m

[$logfile2]
active = true
regex = (xyz) ([0-9]+\\\.[0-9]+\\\.[0-9]+\\\.[0-9]+)
ip=%2

[$logfile3]
regex = (.*)
ip=%9

[/etc/passwd]
numfails = 2
regex = ([0-9]+\\\.[0-9]+\\\.[0-9]+\\\.[0-9]+)
ip=%1
unseen_period = 20m

[/etc/group]
numfails = 2
regex = ([0-9]+\\\.[0-9]+\\\.[0-9]+\\\.[0-9]+)
ip=%1

EOF

my $cfg_file = tmpnam();
open FH, ">$cfg_file"; print FH $cfg_data; close FH;
unlink($jailfile);
my $b = BOIA->new($cfg_file);

is(ref $b, 'BOIA', 'Object is created');
can_ok($b, qw/ version run scan_files process release zap read_config exit_loop run_cmd 
		dryrun list_jail load_jail save_jail /);
is($b->version, '0.1', 'Version is '.$b->version);

diag('--- testing run_cmd');

$b->run_cmd("cp /etc/hosts $logfile1");
sleep 1;
my $content1 = `cat /etc/hosts`;
my $content2 = `cat $logfile1`;
is($content1, $content2, "run_cmd works");

diag('--- testing BOIA basic functionality');

$b->dryrun(1);

my $now = int( (time() / 10) + 0.5 ) * 10 ; #round down
my $release_time1 = $now + 1000;
my $release_time2 = $now + 300;

my @tests = (
	{	
		section => $logfile1,
		data => "172.1.2.3 on x\n192.168.0.99 on z\n172.168.0.1 hi\n172.0.0.9 on k\n127.0.0.1 on a\n172.1.2.3 on h\n10.1.2.3 on justonce",
		logs => [
			'172.1.2.3 has been seen 1 times, not blocking yet',
			'192.168.0.99 is in our network',
			'172.0.0.9 has been seen 1 times, not blocking yet',
			'127.0.0.1 is in our network',
			sprintf("dryrun: echo %s TCP 22 172.1.2.3 1000", $logfile1),
			'blocking 172.1.2.3',
			"Found offending 127.0.0.1 in $logfile1",
			"Found offending 172.0.0.9 in $logfile1",
			"Found offending 172.1.2.3 in $logfile1",
			"Found offending 172.1.2.3 in $logfile1",
			"Found offending 192.168.0.99 in $logfile1",
			"10.1.2.3 has been seen 1 times, not blocking yet",
			"Found offending 10.1.2.3 in $logfile1"
			],
		jail => {
			$logfile1 => {
				'172.0.0.9' => {
					'count' => 1,
					'lastseen' => ignore(),
				},
				'172.1.2.3' => {
					'count' => 2,
					'release_time' => $release_time1,
					'lastseen' => ignore(),
				},
				'10.1.2.3' => {
					'count' => 1,
					'lastseen' => ignore(),
				}
			},
		},
	},
	{
		section => $logfile2,
		data => "xyz 172.2.0.1\nxyz 192.168.0.2\nxyz 172.1.2.3\n172.5.0.1\n",
		logs => [
			'192.168.0.2 is in our network',
			'blocking 172.1.2.3',
			'blocking 172.2.0.1',
			sprintf('dryrun: echo global blockcmd %s 172.1.2.3', $logfile2),
			sprintf('dryrun: echo global blockcmd %s 172.2.0.1', $logfile2),
			"Found offending 172.1.2.3 in $logfile2",
			"Found offending 172.2.0.1 in $logfile2", 
			"Found offending 192.168.0.2 in $logfile2",
			],
		jail => {
			$logfile1 => {
				'172.0.0.9' => {
					'count' => 1,
					'lastseen' => ignore(),
				},
				'172.1.2.3' => {
					'count' => 2,
					'release_time' => $release_time1,
					'lastseen' => ignore(),
				},
				'10.1.2.3' => {
					'count' => 1,
					'lastseen' => ignore(),
				}
			},
			$logfile2 => {
				'172.2.0.1' => {
					'count' => 1,
					'release_time' => $release_time2,
					'lastseen' => ignore(),
				},
				'172.1.2.3' => {
					'count' => 1,
					'release_time' => $release_time2,
					'lastseen' => ignore(),
				}
				
			},
		},
	},
	{
		section => '/etc/passwd',
		data => "1234 20.1.2.3\n5678 20.1.2.4\n",
		logs => [
			'20.1.2.3 has been seen 1 times, not blocking yet',
			'20.1.2.4 has been seen 1 times, not blocking yet',
			'Found offending 20.1.2.3 in /etc/passwd',
			'Found offending 20.1.2.4 in /etc/passwd'
			],
		jail => {
			$logfile1 => {
				'172.0.0.9' => {
					'count' => 1,
					'lastseen' => ignore(),
				},
				'172.1.2.3' => {
					'count' => 2,
					'release_time' => $release_time1,
					'lastseen' => ignore(),
				},
				'10.1.2.3' => {
					'count' => 1,
					'lastseen' => ignore(),
				}
			},
			$logfile2 => {
				'172.2.0.1' => {
					'count' => 1,
					'release_time' => $release_time2,
					'lastseen' => ignore(),
				},
				'172.1.2.3' => {
					'count' => 1,
					'release_time' => $release_time2,
					'lastseen' => ignore(),
				}
				
			},
			'/etc/passwd' => {
				'20.1.2.3' => {
					'count' => 1,
					'lastseen' => ignore(),
				},
				'20.1.2.4' => {
					'count' => 1,
					'lastseen' => ignore(),
				}
			},
		},
	},
	{
		section => '/etc/group',
		data => "1234 20.1.2.3\n5678 20.1.2.4\n",
		logs => [
			'20.1.2.3 has been seen 1 times, not blocking yet',
			'20.1.2.4 has been seen 1 times, not blocking yet',
			'Found offending 20.1.2.3 in /etc/group',
			'Found offending 20.1.2.4 in /etc/group'
			],
		jail => {
			$logfile1 => {
				'172.0.0.9' => {
					'count' => 1,
					'lastseen' => ignore(),
				},
				'172.1.2.3' => {
					'count' => 2,
					'release_time' => $release_time1,
					'lastseen' => ignore(),
				},
				'10.1.2.3' => {
					'count' => 1,
					'lastseen' => ignore(),
				}
			},
			$logfile2 => {
				'172.2.0.1' => {
					'count' => 1,
					'release_time' => $release_time2,
					'lastseen' => ignore(),
				},
				'172.1.2.3' => {
					'count' => 1,
					'release_time' => $release_time2,
					'lastseen' => ignore(),
				}
				
			},
			'/etc/passwd' => {
				'20.1.2.3' => {
					'count' => 1,
					'lastseen' => ignore(),
				},
				'20.1.2.4' => {
					'count' => 1,
					'lastseen' => ignore(),
				}
			},
			'/etc/group' => {
				'20.1.2.3' => {
					'count' => 1,
					'lastseen' => ignore(),
				},
				'20.1.2.4' => {
					'count' => 1,
					'lastseen' => ignore(),
				}
			},
		},
	},

	{
	},
);

my $i=1;
foreach my $test (@tests) {
	next unless ($test && defined($test->{section}) && defined($test->{data}));

	$syslog = [];
	ok($b->process($test->{section}, $test->{data}), "$i: process() ran fine");

	#round down the release_times for proper comparison
	while ( my ($ip, $sections) = each ( %{ $b->{jail} } ) ) {
		while (my ($log, $section) = each(%$sections) ) {
			next unless exists $section->{release_time};
			my $t = $section->{release_time};
			$t = int( ($t / 10) + 0.5 ) * 10;
			$section->{release_time} = $t;
		}
	}

	cmp_bag($syslog, $test->{logs}, "$i: logs are good");
	cmp_deeply($b->{jail}, $test->{jail}, "$i: Internal data structure looks good");
	$i++;
}

ok(!-e $jailfile, "jail file is not created yet");

diag("--- Testing the release()");
$syslog = [];

# fake passing time
$b->{jail}->{$logfile1}->{'172.1.2.3'}->{release_time} = time() - 20;
$b->{jail}->{$logfile2}->{'172.2.0.1'}->{release_time} = time() - 20;
$b->{jail}->{$logfile1}->{'10.1.2.3'}->{lastseen} = time() - 10*60 -1;
$b->{jail}->{'/etc/passwd'}->{'20.1.2.3'}->{lastseen} = time() - 20*60 -1;
$b->{jail}->{'/etc/passwd'}->{'20.1.2.4'}->{lastseen} = time() - 10*60 -1;
$b->{jail}->{'/etc/group'}->{'20.1.2.3'}->{lastseen} = time() - 20*60 -1;
$b->{jail}->{'/etc/group'}->{'20.1.2.4'}->{lastseen} = time() - 60*60 -1;

$b->release();

ok(-s $jailfile, "jail file exists now");

cmp_bag($syslog, ["dryrun: echo global unblockcmd $logfile2 172.2.0.1",
		  "dryrun: echo unblock $logfile1 172.1.2.3",
		  "unblocking 172.1.2.3 for $logfile1", 
		  "unblocking 172.2.0.1 for $logfile2" ], "looks like release() worked");
my $jail =  {


	$logfile1 => {
		'172.0.0.9' => {
			'count' => 1,
			'lastseen' => ignore(),
		}
	},
	$logfile2 => {
		'172.1.2.3' => {
			'count' => 1,
			'release_time' => $release_time2,
			'lastseen' => ignore(),
		},
	},
	'/etc/group' => {
		'20.1.2.3' => {
			'count' => 1,
			'lastseen' => ignore(),
		}
	},
	'/etc/passwd' => {
		'20.1.2.4' => {
			'count' => 1,
			'lastseen' => ignore(),
		},
	},
};
cmp_deeply($b->{jail}, $jail, "release() worked");

diag("--- Testing load_jail()");

$b->save_jail();
my $b2 = BOIA->new($cfg_file);
$b2->load_jail();
cmp_deeply($b2->{jail}, $b->{jail}, "Jail loaded alright");

diag("--- Testing zap()");
$syslog = [];

$b->zap();

cmp_deeply($b->{jail}, {}, "Jail got zapped");
cmp_bag($syslog, [ "dryrun: echo global zap $logfile2",
		   "dryrun: echo zap $logfile1",
		   "dryrun: echo global zap $logfile3",
		   'dryrun: echo global zap /etc/group',
		   'dryrun: echo global zap /etc/passwd',
		 ], 
	"Ran commands correctly it seems");

diag("--- Testing scan_files()");
$syslog = [];

open FH, ">$logfile1"; 
print FH "172.1.2.3 on x\n192.168.0.99 on z\n172.168.0.1 hi\n172.0.0.9 on k\n127.0.0.1 on a\n172.1.2.3 on h\n";
close FH;
open FH, ">$logfile2";
print FH "xyz 172.2.0.1\nxyz 192.168.0.2\nxyz 172.1.2.3\n172.5.0.1\n";
close FH;

$now = int( (time() / 10) + 0.5 ) * 10 ; #round down
$release_time1 = $now + 1000;
$release_time2 = $now + 300;

$jail = {
	$logfile1 => {
		'172.0.0.9' => {
			'count' => 1,
			'lastseen' => ignore(),
		},
		'172.1.2.3' => {
			'count' => 2,
			'release_time' => $release_time1,
			'lastseen' => ignore(),
		}
	},
	$logfile2 => {
		'172.2.0.1' => {
			'count' => 1,
			'release_time' => $release_time2,
			'lastseen' => ignore(),
		},
		'172.1.2.3' => {
			'count' => 1,
			'release_time' => $release_time2,
			'lastseen' => ignore(),
		}
	},
};

my $jail_list = [
          [ '172.2.0.1', $logfile2, 1, $release_time2],
          [ '172.1.2.3', $logfile1, 2, $release_time1],
          [ '172.1.2.3', $logfile2, 1, $release_time2]
];


unlink($jailfile);
$b->scan_files();

#round down the release_times for proper comparison
while ( my ($ip, $sections) = each ( %{ $b->{jail} } ) ) {
	while (my ($log, $section) = each(%$sections) ) {
		next unless exists $section->{release_time};
		my $t = $section->{release_time};
		$t = int( ($t / 10) + 0.5 ) * 10;
		$section->{release_time} = $t;
	}
}

cmp_deeply($b->{jail}, $jail, "scan_files() generated correct internal data structure");
cmp_bag($syslog, [
          "dryrun: echo global blockcmd $logfile2 172.2.0.1",
          "blocking 172.2.0.1",
          "192.168.0.2 is in our network",
          "dryrun: echo global blockcmd $logfile2 172.1.2.3",
          "blocking 172.1.2.3",
          "172.1.2.3 has been seen 1 times, not blocking yet",
          "192.168.0.99 is in our network",
          "172.0.0.9 has been seen 1 times, not blocking yet",
          "127.0.0.1 is in our network",
          "dryrun: echo $logfile1 TCP 22 172.1.2.3 1000",
	  "dryrun: echo global blockcmd $logfile3 %9",
	  "dryrun: echo global blockcmd $logfile3 %9",
          "blocking 172.1.2.3",
	  "Failed reading jail file $jailfile",
	  "Found offending 127.0.0.1 in $logfile1",
	  "Found offending 172.0.0.9 in $logfile1",
	  "Found offending 172.1.2.3 in $logfile1",
	  "Found offending 172.1.2.3 in $logfile1",
	  "Found offending 172.1.2.3 in $logfile2",
	  "Found offending 172.2.0.1 in $logfile2",
	  "Found offending 192.168.0.2 in $logfile2",
	  "Found offending 192.168.0.99 in $logfile1",
        ], "scan_files() seemed to work");

ok(-s $jailfile, "jail file is created");
cmp_bag($b->list_jail(), $jail_list, "list_jail() works");

unlink($jailfile);

unlink $cfg_file;
unlink $logfile1;
unlink $logfile2;
unlink $logfile3;
rmtree($workdir);

