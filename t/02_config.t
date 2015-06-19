use Test::More tests => 2*5+(5+28)+1+6;
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
unseen_period = 30m

[/etc/passwd]
name = mydesc
port = 22
protocol = TCP 
regex = (\d+\.\d+\.\d+\.\d+)
ip=%1
blockcmd = du -h
unblockcmd = df -h
zapcmd = mount
filter = echo hi

numfails = 5
unseen_period = 1h

[/etc/group]
active = false
unseen_period = 2s

EOF
	  result  => { 
		errors => [],
          	active_sections => [ '/etc/passwd' ]
	  },
	  cfg     => bless( {
			   '/etc/group' => {
				'active' => 'false',
				'unseen_period' => '2s',
			   },
			   '_' => {
				'numfails' => '3',
				'myhosts' => 'localhost 192.168.0.0/24',
				'blocktime' => 5940,
				'blockcmd' => 'ls -l',
				'workdir' => '/tmp/boia',
				'unseen_period' => 1800,
			  },
			  '/etc/passwd' => {
				'protocol' => 'TCP',
				'blockcmd' => 'du -h',
				'ip' => '%1',
				'unblockcmd' => 'df -h',
				'port' => '22',
				'numfails' => '5',
				'regex' => '(\\d+\\.\\d+\\.\\d+\\.\\d+)',
				'zapcmd' => 'mount',
				'unseen_period' => 3600,
				'filter' => 'echo hi',
				'name' => 'mydesc',
		    	}
		}, 'Config::Tiny' ),
	},
	
	{ content => <<'EOF',
blockcmd = lsx -l
unblockcmd = pwdxyz --help
zapcmd = perlx -w
startcmd = yupeeeeee
filter = calculator

myhosts = localhost 192.168.0.0/24
blocktime = 1d
numfails = 3
paramx = valuex
workdir=/tmp/boiax
unseen_period = 10y
name = something

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
unseen_period = 1century

[/etc/group]
blocktime = 9y
something = something_else
unseen_period = 20 years 
numfails=abc123def
zapcmd=beep

[/etc/hosts]
blockcmd=/bin/echo
regex=(\d+)
unseen_period=10m

EOF
	result  => { 
		errors => [
			"Invalid parameter 'paramx' in global section",
			'Global section has an invalid unblockcmd',
			'Global section has an invalid zapcmd',
			'Global section has an invalid startcmd',
			'Global section has an invalid filter',
			'Global section has an invalid unseen_period',
			"Invalid parameter 'name' in global section",
			"Invalid parameter 'something' in /etc/group section",
			'/etc/group has no regex',
			'/etc/group has no blockcmd',
			'/etc/group does not have a proper zapcmd',
			'/etc/group has an invalid blocktime',
			'/etc/group has an invalid unseen_period',
			'numfails in /etc/group section must be numeric',
			'/etc/passwd has a bad regex',
			'/etc/passwd does not have a proper blockcmd',
			'/etc/passwd does not have a proper unblockcmd',
			'/etc/passwd does not have a proper zapcmd',
			'/etc/passwd has an invalid unseen_period',
		],
          	active_sections => [ ],
		},
	cfg     => bless( {
			   '/etc/group' => {
				'blocktime' => '9y',
				'unseen_period' => '20 years',
				'something' => 'something_else',
				'numfails'  => 'abc123def',
				'zapcmd' => 'beep',
			   },
			   '/etc/hosts' => {
				'blockcmd' => '/bin/echo',
				'regex'	   => '(\d+)',
				'unseen_period' => 600,
			   },		   
			   '_' => {
				'numfails' => '3',
				'myhosts' => 'localhost 192.168.0.0/24',
				'blocktime' => 86400,
				'blockcmd' => 'lsx -l',
				'zapcmd' => 'perlx -w',
				'unblockcmd' => 'pwdxyz --help',
				'paramx' => 'valuex',
				'workdir' => '/tmp/boiax',
				'unseen_period' => '10y',
				'startcmd' => 'yupeeeeee',
				'filter' => 'calculator',
				'name'	=> 'something',
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
				'zapcmd' => 'mountx',
				'unseen_period' => '1century',
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
unseen_period = 2h
filter = echo global filter
startcmd = echo globalstart

[/etc/passwd]
port = 22
protocol = TCP 
regex = (\d+\.\d+\.\d+\.\d+)
ip=%1
blockcmd = du -h
unblockcmd = df -h
zapcmd = mount
filter = echo hey

blocktime = 12h
numfails = 1

[/etc/group]
active = true
regex = (\d{1,3}\.\d+\.\d+\.\d+)
unseen_period = 30m
startcmd = echo mystart

EOF

my %get_tests = (
	'_' => { 
		blockcmd => 'ls -l',
		unblockcmd => 'pwd --help',
		zapcmd	=> 'perl -w',
		blocktime => 5940,
		numfails => 3,
		unseen_period => 7200,
		filter => 'echo global filter',
		startcmd => 'echo globalstart'
	},
	'/etc/passwd' => {
		blockcmd => 'du -h',
		unblockcmd => 'df -h',
		zapcmd	=> 'mount',
		blocktime => 43200,
		numfails => 1,
		protocol => 'TCP',
		port => 22,
		unseen_period => 7200,
		filter => 'echo hey',
		startcmd => 'echo globalstart'

	},
	'/etc/group' => {
		blockcmd => 'ls -l',
		unblockcmd => 'pwd --help',
		zapcmd	=> 'perl -w',
		blocktime => 5940,
		numfails => 3,
		protocol => undef,
		port => undef,
		unseen_period => 1800,
		filter => 'echo global filter',
		startcmd => 'echo mystart'
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

diag('---Testing time parsing');

my %times = (
	'90y' 	=> undef,
	'10'  	=> 10,
	'100s' 	=> 100,
	'5m'	=> 300,
	'10h'	=> 36000,
	'10d'   => 3600*24*10,
);
while (my ($str, $result) = each(%times)) {
	my $seconds = BOIA::Config->parse_time($str);
	if ($result) {
		is($seconds, $result, "$str is $seconds seconds");
	} else {
		ok(!defined $seconds, "$str is invalid");
	}
}

unlink($file);
