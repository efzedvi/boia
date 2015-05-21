use Test::More tests => 6;
use warnings;
use strict;

use Test::Deep;
use File::Temp qw( :POSIX );

use lib './lib';

use Sys::Syslog qw(:macros);
use BOIA::Log;

diag("--- Testing BOIA::Log");

my @stderr = ();
my @syslog = ();

no warnings 'redefine';
local *BOIA::Log::write_stderr = sub { my ($c, $t, $s) = @_; push @stderr, $s };
local *BOIA::Log::write_syslog = sub { my ($c, $l, $s) = @_; push @syslog, $s };
use warnings 'redefine';

my $log = BOIA::Log->new(LOG_DEBUG, BOIA_LOG_SYSLOG | BOIA_LOG_STDERR);

isa_ok($log, 'BOIA::Log');
can_ok($log, qw( set_options write close ));

my $log2 = BOIA::Log->new(undef, BOIA_LOG_STDERR);

is($log2->{type}, $log->{type}, "BOIA::Log is a singleton");
$log->set_options(undef, BOIA_LOG_SYSLOG | BOIA_LOG_STDERR);
is($log2->{type}, BOIA_LOG_SYSLOG | BOIA_LOG_STDERR, "set_options works");

$log->write(undef, 'This is a log message');

cmp_bag(\@stderr, [ 'This is a log message' ], 'Wrote to stderr');
cmp_bag(\@syslog, [ 'This is a log message' ], 'Wrote to syslog');

