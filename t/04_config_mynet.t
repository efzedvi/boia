use Test::More tests => 14;
use warnings;
use strict;

use Test::Deep;
use File::Temp qw( :POSIX );

use lib './lib';

use BOIA::Config;

diag("--- Testing BOIA::Config with respect to myhosts paramter");

my $file = tmpnam();

my $content = <<'EOF',
blockcmd = ls -l
unblockcmd = pwd --help
zapcmd = perl -w

myhosts = 192.168.0.0/24, 192.168.1.1 10.0.1.0/16 FE80::0202:B3FF:FE1E:0000/112
blocktime = 99m
numfails = 3

[passwd]
logfile = /etc/passwd
port = 22
protocol = TCP 
regex = (\d+\.\d+\.\d+\.\d+)
ip=%1
blockcmd = du -h
unblockcmd = df -h
zapcmd = mount 

blocktime = 12h
numfails = 5

[/etc/group]
active = false

EOF

unlink($file);
open FH, ">$file";
print FH $content;
close FH;	

my $cfg = BOIA::Config->new($file);
my $result = $cfg->parse();

my %tests = ( 	'192.168.0.99' => 1,
		'192.168.0.199' => 1,
		'192.168.0.1' => 1,
		'192.168.1.1' => 1,
		'192.168.1.19' => 0,
		'127.0.0.1' => 1,
		'127.0.0.127' => 1,
		'192.168.2.9' => 0,
		'10.0.90.200' => 1,
		'10.1.90.200' => 0,
		'FE80::0202:B3FF:FE1E:8329' => 1,
		'FE80::0202:B3FF:FE1E:ABCD' => 1,
		'FE80::1:0202:B3FF:FE1E:ABCD' => 0,
		'FE80:::0202:B4FF:FE1E:ABCD' => 0,
	    );

while ( my ($ip, $result) = each(%tests)) {
	is($cfg->is_my_host($ip), $result, "$ip : $result");
}

unlink($file);
