use Test::More tests => 1*3;
use warnings;
use strict;

use Test::Deep;
use File::Temp qw( :POSIX );

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
	  result  => { 
		errors => [],
          	active_sections => [ '/etc/passwd' ]
		},
	  cfg     => bless({ 
		'/etc/group' => { 'active' => 'false' },
		'_' =>  {
			'numfails' => '3',
			'myhosts' => 'localhost 192.168.0.0/24',
			'blocktime' => 5940,
			'blockcmd' => 'ls -l',
			'zapcmd' => 'perl -w',
			'unblockcmd' => 'pwd --help'
			},
		'/etc/passwd' => {
			'protocol' => 'TCP',
			'blockcmd' => 'du -h',
			'ip' => '%1',
			'unblockcmd' => 'df -h',
			'port' => '22',
			'numfails' => '5',
			'blocktime' => 43200,
			'regex' => '(\\d+\\.\\d+\\.\\d+\\.\\d+)',
			'zapcmd' => 'mount'
			}
		}, 'Config::Tiny'),
	},

	{ content => <<'EOF',
EOF
	  result  => { 
		active_sections => [],
		errors => []
	  },
	  cfg     => {},
	},

);

unlink($file);

my $i = 0;
for my $test (@tests) {
	next unless (defined($test->{content}) && $test->{content});
	
	open FH, ">$file";
	print FH $test->{content};
	close FH;	
	my $cfg = BOIA::Config->new($file);
	my $result = $cfg->parse();
	my $sections = $cfg->{active_sections};

	cmp_deeply($result, $test->{result}, "test $i: result is good");
	cmp_deeply($cfg->{cfg}, $test->{cfg},    "test $i: cfg is good");
	cmp_deeply($sections, $test->{result}->{active_sections}, "test $i: sections are good");

	$i++;
}

unlink($file);
