use Test::More tests => 1;
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

no warnings 'redefine';
local *BOIA::Log::write_syslog = sub { my ($c, $l, $s) = @_; push @$syslog, $s };
local *BOIA::run_cmd = sub { 
	my ($c, $s, $v) = @_;
	
	my @a = split(/\s+/, $s);
	return [ 1, $a[1]."\n".$a[2], '' ];
};
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

[$logfile1]
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
	{
		logfile => $logfile1,
		filter => 'echo 10 10.0.0.1',
		data   => "bad:1.2.3.0\n",
		jail   => {
		},
		logs   => {
		}
	},
	
	{
	},
);

use Data::Dumper;

for my $test (@tests) {
	next unless %$test;
	$syslog = [];

	my $section = $test->{logfile};
	my $bc = BOIA::Config->new();
	$bc->{cfg}->{$section}->{filter} = $test->{filter}; 
	$b->process($section, $test->{data});
	ok(1);
	print STDERR Dumper($b->{jail});
	print STDERR Dumper($syslog);
}

unlink($jailfile);
unlink $cfg_file;
unlink $logfile1;
rmtree($workdir);

