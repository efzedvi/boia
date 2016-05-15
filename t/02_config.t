use Test::More tests => 2*5+(5+30)+1+3+6;
use warnings;
use strict;

use Test::Deep;
use File::Temp qw( :POSIX );
use File::Path;

use lib './lib';

use BOIA::Config;

diag("--- Testing BOIA::Config");

my $workdir1 = tmpnam();
my $workdir2 = tmpnam();

my @tests = (
	{ content => <<'EOF',
blockcmd = ls -l
#unblockcmd = pwd --help
#zapcmd = perl -w

myhosts = localhost 192.168.0.0/24
blocktime = 99m
numfails = 3
unseen_period = 30m

[passwd]
logfile = /etc/passwd
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

[hosts]
logfile = /etc/hosts
regex = (.*)
numfails = 0
blocktime =0

[hosts2]
logfile = /etc/hosts
regex = (.+)
numfails = 9
blocktime = 2

[group]
active = false
unseen_period = 2s

[group2]
unseen_period = 2h
regex = ^error.*ip=(.*)
ip = %1
logfile = /etc/group


[tt]
active = true
regex = (.*)

EOF
	  result  => { 
		errors => [],
          	active_sections => bag( 'hosts2', 'hosts', 'passwd', 'group2' ),
		logfile_sections => { '/etc/passwd' => bag('passwd'),
				      '/etc/hosts'  => bag( 'hosts2', 'hosts' ),
				      '/etc/group'  => bag( 'group2' ),
				    },
	  },
	  cfg     => bless( {
			   'tt' => {
				'active' => 'true',
				'regex' => '(.*)',
			   },
			   'group' => {
				'active' => 'false',
				'unseen_period' => '2s',
			   },
			   'group2' => {
				'unseen_period' => '7200',
				'regex' => '^error.*ip=(.*)',
				'ip' => '%1',
				'logfile' => '/etc/group'
			   },

			   '_' => {
				'numfails' => '3',
				'myhosts' => 'localhost 192.168.0.0/24',
				'blocktime' => 5940,
				'blockcmd' => 'ls -l',
				'workdir' => '/tmp/boia',
				'unseen_period' => 1800,
			  },
			  'hosts' => {
				'logfile' => '/etc/hosts',
				'regex' => '(.*)',
				'numfails' => 0,
				'blocktime' => 0,
			  },
			   'hosts2' => {
				'logfile' => '/etc/hosts',
				'regex' => '(.+)',
				'numfails' => 9,
				'blocktime' => 2,
			  },
			  'passwd' => {
				'logfile' => '/etc/passwd',
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
	
	{ content => <<"EOF",
blockcmd = lsxyz -l
unblockcmd = pwdxyz --help
zapcmd = perlx -w
startcmd = yupeeeeee
filter = calculator

myhosts = localhost 192.168.0.0/24
blocktime = 1d
numfails = 3
paramx = valuex
workdir=$workdir2
unseen_period = 10y
name = something

[passwd]
logfile = /etc/passwd
port = 22
protocol = TCP 
regex = (\\d+\\.\\d+\\.\\d+\\.\\d+)(
ip=%1
blockcmd = duxx -h
unblockcmd = dfx -h
zapcmd = mountx 

blocktime = 29s
numfails = 5
unseen_period = 1century

[group]
logfile = /etc/group
blocktime = 9y
something = something_else
unseen_period = 20 years 
numfails=abc123def
zapcmd=beep

[hosts]
logfile = /etc/hosts
blockcmd=/bin/echo
regex=(\\d+)
unseen_period=10m

EOF
	result  => { 
		errors => bag(
			'Invalid parameter \'paramx\' in global section',
                        'Invalid parameter \'name\' in global section',
                        'Global section has an invalid unblockcmd',
                        'Global section has an invalid zapcmd',
                        'Global section has an invalid startcmd',
                        'Global section has an invalid filter',
                        'Global section has an invalid unseen_period',
                        'passwd has a bad regex',
                        'passwd does not have a proper blockcmd',
                        'passwd does not have a proper unblockcmd',
                        'passwd does not have a proper zapcmd',
                        'passwd has an invalid unseen_period',
                        'Invalid parameter \'something\' in group section',
                        'group has no regex',
			'group has no blockcmd',
                        'group does not have a proper zapcmd',
                        'group has an invalid blocktime',
                        'group has an invalid unseen_period',
                        'numfails in group section must be numeric'
		),
          	active_sections => [],
		logfile_sections => {},
		},
	cfg     => bless( {
			   'group' => {
				'logfile' => '/etc/group',
				'blocktime' => '9y',
				'unseen_period' => '20 years',
				'something' => 'something_else',
				'numfails'  => 'abc123def',
				'zapcmd' => 'beep',
			   },
			   'hosts' => {
				'logfile' => '/etc/hosts',
				'blockcmd' => '/bin/echo',
				'regex'	   => '(\d+)',
				'unseen_period' => 600,
			   },		   
			   '_' => {
				'numfails' => '3',
				'myhosts' => 'localhost 192.168.0.0/24',
				'blocktime' => 86400,
				'blockcmd' => 'lsxyz -l',
				'zapcmd' => 'perlx -w',
				'unblockcmd' => 'pwdxyz --help',
				'paramx' => 'valuex',
				'workdir' => $workdir2,
				'unseen_period' => '10y',
				'startcmd' => 'yupeeeeee',
				'filter' => 'calculator',
				'name'	=> 'something',
			  },
			  'passwd' => {
				'logfile' => '/etc/passwd',
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
		logfile_sections => {},
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
	my $logfiles = $cfg->get_active_logfiles();
	unlink($file);

	cmp_deeply($result, $test->{result}, "test $i: result is good");
	cmp_deeply($cfg->{cfg}, $test->{cfg}, "test $i: cfg is good");
	cmp_deeply($sections, $test->{result}->{active_sections}, "test $i: sections are good");
	cmp_bag($logfiles, [ keys %{$test->{result}->{logfile_sections}} ], "test $i: logfiles are good");

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
protocol = tcp

[passwd]
logfile = /etc/passwd
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

[group]
logfile = /etc/group
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
	'passwd' => {
		logfile => '/etc/passwd',
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
	'group' => {
		logfile => '/etc/group',
		blockcmd => 'ls -l',
		unblockcmd => 'pwd --help',
		zapcmd	=> 'perl -w',
		blocktime => 5940,
		numfails => 3,
		protocol => 'tcp',
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
if (scalar( @{$result->{errors}})) {
	use Data::Dumper;
	print STDERR Dumper(@{$result->{errors}});
}
cmp_bag($sections, $result->{active_sections}, "sections are good");

for my $section ( keys %get_tests ) {
	while ( my ($param, $val) = each (%{ $get_tests{$section} }) ) {
		is($cfg->get($section, $param), $val, "$section($param) : ". (defined($val) ? $val : 'undef'));
	}
}
# just to clarify :)
is($cfg->get('passwd', 'numfails', 9), 1, '{passwd}->{numfails} is 1');
is($cfg->get('passwd', 'numfails', 9, 1), 1, '{passwd}->{numfails} is still 1');
is($cfg->get('group', 'protocol', 'UDP', 1), 'UDP', '{group}->{protocol} is UDP');


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
rmtree($workdir1);
rmtree($workdir2);
rmtree('/tmp/boia');

