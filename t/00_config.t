use Test::More tests => 1;
use warnings;
use strict;

use File::Temp qw( :POSIX );
use Config::Tiny;

use lib './lib';

use BOIA::Config;

diag("--- Testing BOIA::Config");

my $file = tmpnam();

my @tests = (
	{ content => <<'EOF',
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
numfails = 5

[/etc/group]
active = false

EOF
	  result  => [],
	  cfg     => {},
	  sections => [],
	},

	{ content => <<'EOF',
EOF
	  result  => [],
	  cfg     => {},
	  sections => [],
	},

);

unlink($file);

for my $test (@tests) {
	next unless defined $test->{content};

	open FH, ">$file";
	print FH $test->{content};
	close FH;	
	my $cfg = BOIA::Config->new($file);
	my $sections = $cfg->get_sections();
	my $result = $cfg->parse();

}

unlink($file);

ok(1, 'hey');
