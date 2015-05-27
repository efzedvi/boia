use Test::More tests => 2*5+(5+19)+1;
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
				    'blockcmd' => 'ls -l',
				    'workdir' => '/tmp/boia',
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
paramx = valuex
workdir=/tmp/boiax

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
something = something_else

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
                        '/etc/passwd does not have a proper zapcmd',
			"Invalid parameter 'paramx' in global section",
			"Invalid parameter 'something' in /etc/group section",
		],
          	active_sections => [ '/etc/group', '/etc/passwd' ],
		},
	cfg     => bless( {
			   '/etc/group' => {
					     'blocktime' => 0,
					     'something' => 'something_else',
					   },
			   '_' => {
				    'numfails' => '3',
				    'myhosts' => 'localhost 192.168.0.0/24',
				    'blocktime' => 62400,
				    'blockcmd' => 'lsx -l',
				    'zapcmd' => 'perlx -w',
				    'unblockcmd' => 'pwdx --help',
				    'paramx' => 'valuex',
				    'workdir' => '/tmp/boiax',
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
	my $sections = $cfg->get_active_sections();
	unlink($file);

	cmp_bag($result->{errors}, $test->{result}->{errors}, "test $i: result is good");
	cmp_deeply($cfg->{cfg}, $test->{cfg}, "test $i: cfg is good");
	cmp_bag($sections, $test->{result}->{active_sections}, "test $i: sections are good");
	cmp_bag($result->{active_sections}, $test->{result}->{active_sections}, "test $i: sections are good");

	$i++;
}


diag("--- Testing get method");

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

my %get_tests = (
	'_' => { 
		blockcmd => 'ls -l',
		unblockcmd => 'pwd --help',
		zapcmd	=> 'perl -w',
		blocktime => 5940,
		numfails => 3
	},
	'/etc/passwd' => {
		blockcmd => 'du -h',
		unblockcmd => 'df -h',
		zapcmd	=> 'mount',
		blocktime => 43200,
		numfails => 1,
		protocol => 'TCP',
		port => 22,
	},
	'/etc/group' => {
		blockcmd => 'ls -l',
		unblockcmd => 'pwd --help',
		zapcmd	=> 'perl -w',
		blocktime => 5940,
		numfails => 3,
		protocol => undef,
		port => undef,
	},
);

my $file = tmpnam();
open FH, ">$file"; 
print FH $cfg_data;
close FH;
my $cfg = BOIA::Config->new($file);
ok($cfg->read($file), "test $i: read file $file");
my $result = $cfg->parse();
my $sections = $cfg->{active_sections};

is(scalar( @{$result->{errors}}), 0, "No errors");
cmp_bag($sections, $result->{active_sections}, "sections are good");

for my $section ( keys %get_tests ) {
	while ( my ($param, $val) = each (%{ $get_tests{$section} }) ) {
		is($cfg->get($section, $param), $val, "$section($param) : ". (defined($val) ? $val : 'undef'));
	}
}

my $cfg2 = BOIA::Config->new($file);
ok(defined $cfg2, "New instance got instantiated");
is($cfg2->get('/etc/passwd', 'blocktime'), $cfg->get('/etc/passwd', 'blocktime'), 'BOIA::Config is a singleton');

is(BOIA::Config->get('/etc/passwd', 'blocktime'), 
   $cfg->get('/etc/passwd', 'blocktime'), 'get() method chan be called statically too');


unlink($file);
