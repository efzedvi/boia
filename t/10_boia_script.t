use Test::More tests => 14+10;
use warnings;
use strict;

use Test::Deep;
use File::Temp qw( :POSIX );
use File::Path;
use Cwd;

use lib './lib';

use BOIA;

my $cwd = getcwd();

my $script = 'script/boia';
my $boia = "$script lib=$cwd/lib";

diag("--- Testing the boia script");

my $syslog = [];

my $workdir = tmpnam()."wd";
my $boialog = tmpnam()."log";
my $logfile1 = tmpnam()."_1";
my $logfile2 = tmpnam()."_2";
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
regex = ([0-9]+\\\.[0-9]+\\\.[0-9]+\\\.[0-9]+) on 
ip=%1
blockcmd = echo %section %protocol %port %ip %blocktime
unblockcmd = echo unblock %section %ip
zapcmd = echo zap %section

blocktime = 1000s
numfails = 2

[$logfile2]
active = true
regex = (xyz) ([0-9]+\\\.[0-9]+\\\.[0-9]+\\\.[0-9]+)
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

diag('---testing the daemon mode');

ok(system("$boia -d -f $cfg_file -l $boialog") >> 8 == 0, 'It is a daemon now');
sleep 2;
my $pid = `cat $workdir/boia.pid`;
like($pid, qr/\d+/, "we have a pid: $pid");

open FH, ">>$logfile1";
print FH "200.0.1.1 on x\n200.1.2.0 on 123\n200.0.1.1 on y\n200.1.2.0 on z\n";
close FH;
open FH, ">>$logfile2";
print FH "xyz 200.0.2.1\nxyz 200.1.2.0\n";
close FH;

print STDERR "appending to monitored files, please wait...  ";
my $i=0;
while ( length($content = `$boia -c list -f $cfg_file 2>/dev/null`) < 100 && $i<30) {
#while ( (-s "$workdir/boia_jail" < 512) && $i<30 ) {
	sleep 1;
	printf STDERR "%c%c%02d", 8, 8, $i++;
}
print STDERR "\n";
#$content = `$boia -c list -f $cfg_file`;
like($content, qr/200\.1\.2\.0\s+$logfile1\s+2\s+20\d\d-\d\d-\d\d,\d\d:\d\d:\d\d/,
	"list seems good so far.");
like($content, qr/200\.1\.2\.0\s+$logfile2\s+1\s+20\d\d-\d\d-\d\d,\d\d:\d\d:\d\d/,
	"list seems good so far..");
like($content, qr/200\.0\.1\.1\s+$logfile1\s+2\s+20\d\d-\d\d-\d\d,\d\d:\d\d:\d\d/,
	"list seems good so far...");
like($content, qr/200\.0\.2\.1\s+$logfile2\s+1\s+20\d\d-\d\d-\d\d,\d\d:\d\d:\d\d/,
	"list seems good so far...");

diag('----- Testing reload with the daemon...');
unlink $boialog;
ok(system("$boia -c reload -f $cfg_file -l $boialog") >> 8 == 0, 'reload seemed to have worked');
sleep 1;
$content = `grep Reread $boialog`;
like($content, qr/Reread the config file: $cfg_file/, "Reload worked");

diag('----- Killing the daemon by sending it INT signal');
kill 'INT', $pid;
sleep 1;
open FH, ">>$logfile2"; print FH "xyz 200.0.2.1\nxyz 200.1.2.0\n"; close FH;
$pid = `cat $workdir/boia.pid`;
ok(!$pid, "pid is gone");

$content = `grep Terminated $boialog`;
like($content, qr/Terminated/, "INT signal worked");

diag('--- Testing parse command');

ok(system("$boia -c parse -f $cfg_file -l $boialog") >> 8 == 0, 'parse seems working');

open FH, ">$cfg_file"; print FH "werid_config_file_content"; close FH;
ok(system("$boia -c parse -f $cfg_file -l $boialog") >> 8 != 0, 'parse seems to work');

open FH, ">$cfg_file"; print FH "regex = (something\n[somelogfile]\nip=%99"; close FH;
ok(system("$boia -c parse -f $cfg_file -l $boialog") >> 8 != 0, 'parse seems to work');

unlink $jailfile;
unlink $cfg_file;
unlink $boialog;
unlink $logfile1;
unlink $logfile2;
rmtree($workdir);

