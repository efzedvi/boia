use Test::More tests => 14;
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
my $boialog = tmpnam();

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
ok(system("$boia -h") >> 8 == 0, '-h worked');
ok(system("$boia -w") >> 8 != 0, '... and it is different from passing an invalid parameter');
ok(system("$boia -c scan -f $cfg_file -l $boialog") >> 8 == 0, '-h worked');
ok(-s $boialog, "Log file has stuff in it");
my $content = `$boia -c list -f $cfg_file`;
like($content, qr/172\.2\.0\.1\s+$logfile2\s+1\s+20\d\d-\d\d-\d\d,\d\d:\d\d:\d\d/,
	"list seems good so far");
like($content, qr/172\.1\.2\.3\s+$logfile1\s+2\s+20\d\d-\d\d-\d\d,\d\d:\d\d:\d\d/,
	"list seems good still");
like($content, qr/172\.1\.2\.3\s+$logfile2\s+1\s+20\d\d-\d\d-\d\d,\d\d:\d\d:\d\d/,
	"list seems good");

ok(system("$boia -c zap -f $cfg_file -l $boialog") >> 8 == 0, 'zap worked');
is(`$boia -c list -f $cfg_file`, "No offending IP address found yet\n", 'zap really worked');

ok(system("$boia -c parse -f $cfg_file -l $boialog") >> 8 == 0, 'parse seems working');

open FH, ">$cfg_file"; print FH "werid_config_file_content"; close FH;
ok(system("$boia -c parse -f $cfg_file -l $boialog") >> 8 != 0, 'parse seems to work');

open FH, ">$cfg_file"; print FH "regex = something\n[somelogfile]\nip=%99"; close FH;
ok(system("$boia -c parse -f $cfg_file -l $boialog") >> 8 != 0, 'parse seems to work');

unlink $jailfile;
unlink $cfg_file;
unlink $boialog;
unlink $logfile1;
unlink $logfile2;
rmtree($workdir);

