use Test::More tests => 3;
use warnings;
use strict;

use Test::Deep;
use File::Temp qw( :POSIX );
use File::Path;

use lib './lib';

use BOIA::Log;
use BOIA;


diag("--- Testing BOIA handling log rotation");

my $syslog = [];
my $now = 1000000;

no warnings 'redefine';
local *BOIA::Log::write_syslog = sub { my ($c, $l, $s) = @_; push @$syslog, $s };
local *BOIA::_now = sub { $now; };
use warnings 'redefine';

BOIA::Log->open({ level => LOG_DEBUG, syslog => 1});

#-----------------------
my $workdir = tmpnam();
my $logfile1 = tmpnam()."1";
my $logfile2 = tmpnam()."2";
my $logfile3 = tmpnam()."3";

my $jailfile = "$workdir/boia_jail";

open FH, ">$logfile1"; print FH "data\n"; close FH;
open FH, ">$logfile2"; print FH "data\n"; close FH;

my $cfg_data = <<"EOF",
blockcmd = echo global blockcmd %section %ip
unblockcmd = echo global unblockcmd %section %ip
zapcmd = echo global zap %section
startcmd = echo startcmd %section %name

workdir = $workdir

myhosts = localhost 192.168.0.0/24
blocktime = 5m
numfails = 1

[$logfile1]
name = num1
port = %2
protocol = TCP 
regex = ([0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+) on (\\d+)
ip=%1
blockcmd = echo %section %protocol %port %ip %blocktime %name
unblockcmd = echo unblock %section %ip %port
zapcmd = echo zap %section

blocktime = 1000s
numfails = 2
unseen_period = 10m

[$logfile2]
active = true
regex = xyz ([0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+)
ip=%2

EOF

my $cfg_file = tmpnam();
open FH, ">$cfg_file"; print FH $cfg_data; close FH;
my $b = BOIA->new($cfg_file);

my @steps = ();

sub test {
	my (@test_steps) = @_;

	push @test_steps, { delay => 1, code  => sub { $b->exit_loop() }, };

	@steps = @test_steps;

	$SIG{ALRM} = sub {
		my $task = shift @steps;
		$task->{code}->() if defined $task->{code};
		alarm $task->{delay} || 1;
	};

	alarm 1;

	unlink($jailfile);
	$b->{jail} = {};
	$syslog = [];
	$b->loop(1);
}

my @tests = (
	{	title => 'case 1',
		steps => [
			{ delay => 1,
			  code  => sub { 
				open FH, ">> $logfile1"; print FH "1.0.0.1 on 23\n"; close FH;
				},
			},
			{ delay => 1,
			  code  => sub { 
				unlink $logfile1;
				},
			},
			{ delay => 1,
			  code  => sub {
				open FH, ">> $logfile1"; print FH "1.0.0.1 on 23\n"; close FH;  
				},
			},
		],
		result => {
			$logfile1 => {
				'1.0.0.1' => {
					'ports' => { '23' => 1 },
					'count' => 2,
					'blocktime' => 1000,
					'lastseen' => $now,
					'release_time' => $now+1000
				}
			}
		}
	},
	{	title => 'case 2',
		steps => [
			{ delay => 1,
			  code  => sub { 
				open FH, ">> $logfile1"; print FH "1.0.0.2 on 23\n"; close FH;
				},
			},
			{ delay => 1,
			  code  => sub { 
				unlink $logfile1;
				open FH, ">> $logfile1"; print FH "1.0.0.2 on 23\n"; close FH;  
				},
			},
		],
		result => {
			$logfile1 => {
				'1.0.0.2' => {
					'ports' => { '23' => 1 },
					'count' => 2,
					'blocktime' => 1000,
					'lastseen' => $now,
					'release_time' => $now+1000
				}
			}
		}
	},
	{	title => 'case 3',
		steps => [
			{ delay => 1,
			  code  => sub { 
				open FH, ">> $logfile1"; print FH "1.0.0.3 on 23\n"; close FH;
				},
			},
			{ delay => 1,
			  code  => sub { 
				rename $logfile1, $logfile3;
				open FH, ">> $logfile1"; print FH "1.0.0.3 on 23\n"; close FH;  
				},
			},
		],
		result => {
			$logfile1 => {
				'1.0.0.3' => {
					'ports' => { '23' => 1 },
					'count' => 2,
					'blocktime' => 1000,
					'lastseen' => $now,
					'release_time' => $now+1000
				}
			}
		}
	},




);


#use Data::Dumper;

for my $test (@tests) {
	diag($test->{title});
	test(@{ $test->{steps} });
#	print STDERR Dumper($b->{jail});
	cmp_deeply($b->{jail}, $test->{result}, "internal data structure is correct");
}

unlink($jailfile);
unlink $cfg_file;
unlink $logfile1;
unlink $logfile2;
unlink $logfile3;
rmtree($workdir);

