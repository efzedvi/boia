use Test::More tests => 3;
use warnings;
use strict;

use Test::Deep;
use File::Temp qw( :POSIX );

use lib './lib';

use BOIA;

diag("--- Testing BOIA");

my @stderr = ();
my @syslog = ();

no warnings 'redefine';
local *BOIA::Log::write_stderr = sub { my ($c, $t, $s) = @_; push @stderr, $s };
local *BOIA::Log::write_syslog = sub { my ($c, $l, $s) = @_; push @syslog, $s };
use warnings 'redefine';

#-----------------------

my $logfile1 = tmpnam();
my $logfile2 = tmpnam();

open FH, ">$logfile1"; print FH "data\n"; close FH;
open FH, ">$logfile2"; print FH "data\n"; close FH;

my $cfg_data = <<"EOF",
blockcmd = ls -l
unblockcmd = pwd --help
zapcmd = perl -w

myhosts = localhost 192.168.0.0/24
blocktime = 99m
numfails = 3

[$logfile1]
port = 22
protocol = TCP 
regex = ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)
ip=%1
blockcmd = du -h
unblockcmd = df -h
zapcmd = mount 

blocktime = 12h
numfails = 1

[$logfile2]
active = true
regex = ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)

EOF

my $cfg_file = tmpnam();
open FH, ">$cfg_file"; print FH $cfg_data; close FH;
my $b = BOIA->new($cfg_file);

is(ref $b, 'BOIA', 'Object is created');
can_ok($b, qw/ version run scan_files process release zap read_config exit_loop run_cmd /);
is($b->version, '0.1', 'Version is '.$b->version);



unlink $cfg_file;
unlink $logfile1;
unlink $logfile2;
