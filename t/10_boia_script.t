use Test::More tests => 2;
use warnings;
use strict;

use Test::Deep;
use File::Temp qw( :POSIX );
use File::Path;

use lib './lib';

use BOIA;

my $script = 'script/boia';
my $boia = "$script lib=./lib";

diag("--- Testing the boia script");

my $syslog = [];

my $workdir = tmpnam();
my $logfile1 = tmpnam()."1";
my $logfile2 = tmpnam()."2";

my $jailfile = "$workdir/boia_jail";

open FH, ">$logfile1";
print FH "172.1.2.3 on x\n192.168.0.99 on z\n172.168.0.1 hi\n172.0.0.9 on k\n127.0.0.1 on a\n172.1.2.3 on h\n";
close FH;
open FH, ">$logfile2";
print FH "xyz 172.2.0.1\nxyz 192.168.0.2\nxyz 172.1.2.3\n172.5.0.1\n";
close FH;

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

ok( -x $script, "$script is executable");
is(`$boia -v`, 'BOIA v'.$BOIA::VERSION."\n", "version is good");

unlink($jailfile);
unlink $cfg_file;
unlink $logfile1;
unlink $logfile2;
rmtree($workdir);

