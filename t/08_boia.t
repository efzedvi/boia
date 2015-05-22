use Test::More tests => 2;
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

my $cfg_data = <<'EOF',
blockcmd = ls -l
unblockcmd = pwd --help
zapcmd = perl -w

myhosts = localhost 192.168.0.0/24
blocktime = 99m
numfails = 3

[/etc/passwd]
port = 22
protocol = TCP 
regex = (\d+\.\d+\.\d+\.\d+)
ip=%1
blockcmd = du -h
unblockcmd = df -h
zapcmd = mount 

blocktime = 12h
numfails = 1

[/etc/group]
active = true
regex = (\d{1,3}\.\d+\.\d+\.\d+)

EOF

my $cfg_file = tmpnam();
open FH, ">$cfg_file"; print FH $cfg_data; close FH;
my $cfg = BOIA->new($cfg_file);

is(ref $cfg, 'BOIA', 'Object is created');
can_ok($cfg, qw/ version run scan_files process release zap read_config exit_loop run_cmd /);

unlink $cfg_file;

