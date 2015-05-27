use Test::More tests => 6+2*3+1+3+1+2+3;
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

BOIA::Log->open(LOG_DEBUG, BOIA_LOG_SYSLOG);

#-----------------------
ok(!defined BOIA->new(), "new() failed as expected");
ok(!defined BOIA->new('/dev/something'), "new() failed as expected again");

my $workdir = tmpnam();
my $logfile1 = tmpnam()."1";
my $logfile2 = tmpnam()."2";

my $jailfile = "$workdir/boia_jail";

open FH, ">$logfile1"; print FH "data\n"; close FH;
open FH, ">$logfile2"; print FH "data\n"; close FH;

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
regex = ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+) on 
ip=%1
blockcmd = echo %section %protocol %port %ip %blocktime
unblockcmd = echo unblock %section %ip
zapcmd = echo zap %section

blocktime = 1000s
numfails = 2

[$logfile2]
active = true
regex = (xyz) ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)
ip=%2

EOF

my $cfg_file = tmpnam();
open FH, ">$cfg_file"; print FH $cfg_data; close FH;
unlink($jailfile);
my $b = BOIA->new($cfg_file);

is(ref $b, 'BOIA', 'Object is created');
can_ok($b, qw/ version run scan_files process release zap read_config exit_loop run_cmd 
		dryrun nozap/);
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
		data => "172.1.2.3 on x\n192.168.0.99 on z\n172.168.0.1 hi\n172.0.0.9 on k\n127.0.0.1 on a\n172.1.2.3 on h",
		logs => [
			'172.1.2.3 has been seen 1 times, not blocking yet',
			'192.168.0.99 is in our network',
			'172.0.0.9 has been seen 1 times, not blocking yet',
			'127.0.0.1 is in our network',
			sprintf("dryrun: echo %s TCP 22 172.1.2.3 1000", $logfile1),
			'blocking 172.1.2.3'
			],
		jail => {
			'172.0.0.9' => {
				$logfile1 => {
					'count' => 1
				}
			},
			'172.1.2.3' => {
				$logfile1 => {
					'count' => 2,
					'release_time' => $release_time1
				}
			}
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
			],
		jail => {
			'172.0.0.9' => {
				$logfile1 => {
					'count' => 1
				}
			},
			'172.2.0.1' => {
				$logfile2 => {
					'count' => 1,
					'release_time' => $release_time2,
				}
			},
			'172.1.2.3' => {
				$logfile2 => {
					'count' => 1,
					'release_time' => $release_time2,
				},
				$logfile1 => {
					'count' => 2,
					'release_time' => $release_time1,
				}
			}
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
$b->{jail}->{'172.1.2.3'}->{$logfile1}->{release_time} = time() - 20;
$b->{jail}->{'172.2.0.1'}->{$logfile2}->{release_time} = time() - 20;

$b->release();

ok(-s $jailfile, "jail file exists now");

cmp_bag($syslog, ["dryrun: echo global unblockcmd $logfile2 172.2.0.1",
		"dryrun: echo unblock $logfile1 172.1.2.3"], "looks like release() worked");
my $jail =  {
	'172.0.0.9' => {
		$logfile1 => {
			'count' => 1
		}
	},
	'172.1.2.3' => {
		$logfile2 => {
			'count' => 1,
			'release_time' => $release_time2,
		},
	}
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
cmp_bag($syslog, [ "dryrun: echo global zap $logfile2", "dryrun: echo zap $logfile1"], 
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
	'172.0.0.9' => {
		$logfile1 => {
			'count' => 1
		}
	},
	'172.2.0.1' => {
		$logfile2 => {
			'count' => 1,
			'release_time' => $release_time2,
		}
	},
	'172.1.2.3' => {
		$logfile2 => {
			'count' => 1,
			'release_time' => $release_time2,
		},
		$logfile1 => {
			'count' => 2,
			'release_time' => $release_time1,
		}
	}
};

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
          "blocking 172.1.2.3"
        ], "scan_files() seemed to work");

ok(-s $jailfile, "jail file is created");

unlink($jailfile);

unlink $cfg_file;
unlink $logfile1;
unlink $logfile2;
rmtree($workdir);

