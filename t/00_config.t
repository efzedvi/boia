use Test::More tests => 1;
use warnings;
use strict;

use File::Temp qw( :POSIX );
use Config::Tiny;

use lib './lib';

use BOIA::Config;

diag("--- Testing BOIA::Config");

ok(1, 'hey');
