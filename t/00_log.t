use Test::More tests => 9;
use warnings;
use strict;

use Test::Deep;
use File::Temp qw( :POSIX );

use lib './lib';

use BOIA::Log;

diag("--- Testing BOIA::Log");

my @stderr = ();
my @syslog = ();

no warnings 'redefine';
local *BOIA::Log::write_stderr = sub { my ($c, $t, $s) = @_; push @stderr, $s };
local *BOIA::Log::write_syslog = sub { my ($c, $l, $s) = @_; push @syslog, $s };
use warnings 'redefine';

my $logfile = tmpnam();

BOIA::Log->open({ level => LOG_DEBUG, syslog => 1, stderr => 1, file => $logfile });

BOIA::Log->write(undef, 'line1');

cmp_bag(\@stderr, [ 'line1' ], 'Wrote to stderr');
cmp_bag(\@syslog, [ 'line1' ], 'Wrote to syslog too');

my $content = `cat $logfile`;
like($content, qr/line1/, "Wrote to the log file");

BOIA::Log->open( { stderr => 0 } );

BOIA::Log->write(undef, 'line2');

cmp_bag(\@stderr, [ 'line1' ], 'Did not write to stderr');
cmp_bag(\@syslog, [ 'line1', 'line2' ], 'But it wrote to syslog');

$content = `cat $logfile`;
like($content, qr/line2/, "Wrote to the log file again");

BOIA::Log->open( { stderr => 1, file => undef } );

BOIA::Log->write(undef, 'line3');

cmp_bag(\@stderr, [ 'line1', 'line3' ], 'Did write to stderr');
cmp_bag(\@syslog, [ 'line1', 'line2', 'line3' ], 'Also it wrote to syslog');

$content = `cat $logfile`;
ok($content !~ m/line3/, "Didn't write to the log file this time");


unlink $logfile;
