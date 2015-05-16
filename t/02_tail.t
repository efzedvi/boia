use Test::More tests => 8;
use warnings;
use strict;

use Test::Deep;
use File::Temp qw( :POSIX );

use lib './lib';

use BOIA::Tail;

diag("--- Testing BOIA::Tail");

my $numfiles = 3;
my @filenames = ();

for(my $i=0; $i<$numfiles; $i++) {
	my $fname = tmpnam();
	push @filenames, $fname;
	open FH, ">>$fname";
	print FH "data0 #$i\n";
	close FH;
}

my $bt = BOIA::Tail->new( qw( /etc/passwd /etc/group ) );
ok($bt, 'Object created');

cmp_bag( [keys %{$bt->{files}}], [ qw( /etc/passwd /etc/group ) ], 'Files are set');

$bt->set_files( qw( /etc/hosts /etc/passwd ) );
cmp_bag( [keys %{$bt->{files}}], [ qw( /etc/passwd /etc/hosts ) ], 'Files are set again');

$bt->set_files( qw( /etc/group /etc/something ) );
cmp_bag( [keys %{$bt->{files}}], [ qw( /etc/group ) ], 'Files are set yet again');

$bt->set_files(@filenames);
cmp_bag( [keys %{$bt->{files}}], \@filenames, 'Files are set yet again 2');

my $res = $bt->tail(6);
ok(!$res, "Nothing read, ofcourse");

my $i=0;
my $count = 0;
my $ph = {};
foreach my $fname (@filenames) {
	next if $i++ % 2;
	open FH, ">>$fname";
	my $data = "$count:line$i\nline2$i\n";
	print FH $data;
	close FH;
	$count++;
	$ph->{$fname} = $data;
}

$res = $bt->tail(9);
is(scalar(keys %$res), $count, "We have data");
cmp_deeply($res, $ph, "data is good");

unlink($_) foreach (@filenames);

