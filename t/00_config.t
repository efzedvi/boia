use Test::More tests => 2*4;
use warnings;
use strict;

use Test::Deep;
use File::Temp qw( :POSIX );

use lib './lib';

use BOIA::Config;

diag("--- Testing BOIA::Config");


my @tests = (
	{ content => <<'EOF',
blockcmd = ls -l
#unblockcmd = pwd --help
#zapcmd = perl -w

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
	  cfg     => bless( {
			   '/etc/group' => {
					     'active' => 'false'
					   },
			   '_' => {
				    'numfails' => '3',
				    'myhosts' => 'localhost 192.168.0.0/24',
				    'blocktime' => 5940,
				    'blockcmd' => 'ls -l'
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
			 }, 'Config::Tiny' ),
	},
	
	{ content => <<'EOF',
blockcmd = lsx -l
unblockcmd = pwdx --help
zapcmd = perlx -w

myhosts = localhost 192.168.0.0/24
blocktime = 1d
numfails = 3

[/etc/passwd]
port = 22
protocol = TCP 
regex = (\d+\.\d+\.\d+\.\d+)(
ip=%1
blockcmd = duxx -h
unblockcmd = dfx -h
zapcmd = mountx 

blocktime = 29s
numfails = 5

[/etc/group]
blocktime = 9y

EOF
	result  => { 
		errors => [ 
			'Global section has an invalid blockcmd',
                        'Global section has an invalid zapcmd',
                        '/etc/group has no regex',
                        '/etc/group does not have a proper blockcmd',
                        '/etc/group does not have a proper zapcmd',
                        '/etc/passwd has a bad regex',
                        '/etc/passwd does not have a proper blockcmd',
                        '/etc/passwd does not have a proper unblockcmd',
                        '/etc/passwd does not have a proper zapcmd'
		],
          	active_sections => [ '/etc/group', '/etc/passwd' ],
		},
	cfg     => bless( {
			   '/etc/group' => {
					     'blocktime' => 0
					   },
			   '_' => {
				    'numfails' => '3',
				    'myhosts' => 'localhost 192.168.0.0/24',
				    'blocktime' => 62400,
				    'blockcmd' => 'lsx -l',
				    'zapcmd' => 'perlx -w',
				    'unblockcmd' => 'pwdx --help'
				  },
			   '/etc/passwd' => {
					      'protocol' => 'TCP',
					      'blockcmd' => 'duxx -h',
					      'ip' => '%1',
					      'unblockcmd' => 'dfx -h',
					      'port' => '22',
					      'numfails' => '5',
					      'blocktime' => 29,
					      'regex' => '(\\d+\\.\\d+\\.\\d+\\.\\d+)(',
					      'zapcmd' => 'mountx'
					    }
			 }, 'Config::Tiny' ),
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


my $i = 0;
for my $test (@tests) {
	next unless (defined($test->{content}) && $test->{content});

	my $file = tmpnam();
	open FH, ">$file";
	print FH $test->{content};
	close FH;
	my $cfg = BOIA::Config->new($file);
	ok($cfg->read($file), "test $i: read file $file");
	my $result = $cfg->parse();
	my $sections = $cfg->{active_sections};
	unlink($file);

use Data::Dumper;
print STDERR Dumper($cfg->{result});

	cmp_deeply($result, $test->{result}, "test $i: result is good");
	cmp_deeply($cfg->{cfg}, $test->{cfg},    "test $i: cfg is good");
	cmp_bag($sections, $test->{result}->{active_sections}, "test $i: sections are good");

	$i++;
}

