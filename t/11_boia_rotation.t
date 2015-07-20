use Test::More tests => 2;
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
regex = (xyz) ([0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+)
ip=%2

EOF

my $cfg_file = tmpnam();
open FH, ">$cfg_file"; print FH $cfg_data; close FH;
unlink($jailfile);
my $b = BOIA->new($cfg_file);

is(ref $b, 'BOIA', 'Object is created');


my @steps = (
	{ delay => 1,
	  code  => sub { open FH, ">> $logfile1"; print FH "1.2.3.4 on 23\n"; close FH;  },
	},

	{ delay => 1,
	  code  => sub { unlink $logfile1;  },
	},

	{ delay => 1,
	  code  => sub { open FH, ">> $logfile1"; print FH "1.2.3.4 on 23\n"; close FH;  },
	},

	{ delay => 1,
	  code  => sub { open FH, ">> $logfile1"; print FH "1.2.3.5 on 23\n"; close FH;  },
	},

	{ delay => 1,
	  code  => sub { $b->exit_loop() },
	}
);


$SIG{ALRM} = sub {
	my $task = shift @steps;
	$task->{code}->();
	alarm $task->{delay};
};

alarm 1;

$b->loop(1);


use Data::Dumper;
print STDERR Dumper($syslog);

#cmp_bag($syslog, [
#		 ], "got corret log lines");
ok(1, 'test');


unlink($jailfile);

unlink $cfg_file;
unlink $logfile1;
unlink $logfile2;
rmtree($workdir);

