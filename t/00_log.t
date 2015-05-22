use Test::More tests => 6;
use warnings;
use strict;

use Test::Deep;

use lib './lib';

use BOIA::Log;

diag("--- Testing BOIA::Log");

my @stderr = ();
my @syslog = ();

no warnings 'redefine';
local *BOIA::Log::write_stderr = sub { my ($c, $t, $s) = @_; push @stderr, $s };
local *BOIA::Log::write_syslog = sub { my ($c, $l, $s) = @_; push @syslog, $s };
use warnings 'redefine';

BOIA::Log->open(LOG_DEBUG, BOIA_LOG_SYSLOG | BOIA_LOG_STDERR);

BOIA::Log->write(undef, 'line1');

cmp_bag(\@stderr, [ 'line1' ], 'Wrote to stderr');
cmp_bag(\@syslog, [ 'line1' ], 'Wrote to syslog too');

BOIA::Log->set_options(undef, BOIA_LOG_SYSLOG);

BOIA::Log->write(undef, 'line2');

cmp_bag(\@stderr, [ 'line1' ], 'Didnot write to stderr');
cmp_bag(\@syslog, [ 'line1', 'line2' ], 'But it wrote to syslog');

BOIA::Log->set_options(undef, BOIA_LOG_SYSLOG | BOIA_LOG_STDERR);

BOIA::Log->write(undef, 'line3');

cmp_bag(\@stderr, [ 'line1', 'line3' ], 'Did write to stderr');
cmp_bag(\@syslog, [ 'line1', 'line2', 'line3' ], 'Also it wrote to syslog');


