use Test::More tests => 4+2*3;
use warnings;
use strict;

use Test::Deep;
use File::Temp qw( :POSIX );

use lib './lib';

use BOIA::Log;
use BOIA;

diag("--- Testing BOIA");

my $syslog = [];
my $cmds   = [];

no warnings 'redefine';
local *BOIA::Log::write_syslog = sub { my ($c, $l, $s) = @_; push @$syslog, $s };
local *BOIA::run_cmd = sub { my ($c, $s, $v) = @_; $s =~ s/(%([a-z]+))/ ( defined $v->{$2} ) ? $v->{$2} : $1 /ge; push @$cmds, $s; };
use warnings 'redefine';

BOIA::Log->open(LOG_DEBUG, BOIA_LOG_SYSLOG);

#-----------------------

my $logfile1 = tmpnam();
my $logfile2 = tmpnam();

open FH, ">$logfile1"; print FH "data\n"; close FH;
open FH, ">$logfile2"; print FH "data\n"; close FH;

my $cfg_data = <<"EOF",
blockcmd = ls -l %section %ip
unblockcmd = pwd --help %section %ip
zapcmd = perl -w

myhosts = localhost 192.168.0.0/24
blocktime = 5m
numfails = 1

[$logfile1]
port = 22
protocol = TCP 
regex = ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+) on 
ip=%1
blockcmd = echo %section %protocol %port %ip %blocktime
unblockcmd = echo %section %ip
zapcmd = echo %section

blocktime = 1000s
numfails = 2

[$logfile2]
active = true
regex = (xyz) ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)
ip=%2

EOF

my $cfg_file = tmpnam();
open FH, ">$cfg_file"; print FH $cfg_data; close FH;
my $b = BOIA->new($cfg_file);

is(ref $b, 'BOIA', 'Object is created');
can_ok($b, qw/ version run scan_files process release zap read_config exit_loop run_cmd /);
is($b->version, '0.1', 'Version is '.$b->version);
cmp_bag($syslog, ['Failed reading jail file /tmp/boia/boia_jail'], "Log is good so far");

my @tests = (
	{	
		section => $logfile1,
		data => "172.1.2.3 on x\n192.168.0.99 on z\n172.168.0.1 hi\n172.0.0.9 on k\n127.0.0.1 on a\n172.1.2.3 on h",
		logs => [
			'172.1.2.3 has been seen 1 times, not blocking yet',
			'192.168.0.99 is in our network',
			'172.0.0.9 has been seen 1 times, not blocking yet',
			'127.0.0.1 is in our network',
			'blocking 172.1.2.3'
			],
		jail => {},
		cmds => [ sprintf("echo %s TCP 22 172.1.2.3 1000", $logfile1) ],
	},
	{
		section => $logfile2,
		data => "xyz 172.2.0.1\nxyz 192.168.0.2\nxyz 172.1.2.3\n172.5.0.1\n",
		logs => [
			'192.168.0.2 is in our network',
			'blocking 172.1.2.3',
			'blocking 172.2.0.1'
			],
		jail => {},
		cmds => [
			 sprintf('ls -l %s 172.1.2.3', $logfile2),
			 sprintf('ls -l %s 172.2.0.1', $logfile2),
			],
	},

	{
	},
);

my $i=1;
foreach my $test (@tests) {
	next unless ($test && defined($test->{section}) && defined($test->{data}));

	$syslog = [];
	$cmds   = [];
	ok($b->process($test->{section}, $test->{data}), "$i: process() ran fine");
	cmp_bag($syslog, $test->{logs}, "$i: logs are good");
	cmp_bag($cmds, $test->{cmds}, "$i: cmds are good"); 

use Data::Dumper;
print STDERR Dumper($b->{jail});

	$i++;
}

unlink $cfg_file;
unlink $logfile1;
unlink $logfile2;

