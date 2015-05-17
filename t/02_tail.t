use Test::More tests => 4*(8+4+4);
use warnings;
use strict;

use Test::Deep;
use File::Temp qw( :POSIX );

use lib './lib';

use BOIA::Tail;

use BOIA::Tail;
use BOIA::Tail::Generic;

my @modules = qw( BOIA::Tail BOIA::Tail::Inotify BOIA::Tail::KQueue BOIA::Tail::Generic );

my $os = '';

if (lc $^O eq 'linux') {
	eval "use BOIA::Tail::Inotify;";
	if (!$@) {
		$os = 'linux';
	}
} elsif ($^O =~ /bsd$/i) {
	eval "use BOIA::Tail::KQueue;";
	if (!$@) {
		$os = 'bsd';
	}
} 


sub basic_01 { # 8
	my ($module) = @_;

	diag("--- running basic_01 for $module");

	my $numfiles = 3;
	my @filenames = ();

	for(my $i=0; $i<$numfiles; $i++) {
		my $fname = tmpnam();
		push @filenames, $fname;
		open FH, ">>$fname";
		print FH "$fname: data0 #$i\n";
		close FH;
	}
	my $bt = $module->new( qw( /etc/passwd /etc/group ) );
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
}


sub delete_01 { #4
	my ($module) = @_;

	diag("--- running delete_01 for $module");

	my $numfiles = 3;
	my @filenames = ();

	for(my $i=0; $i<$numfiles; $i++) {
		my $fname = tmpnam();
		push @filenames, $fname;
		open FH, ">>$fname";
		print FH "$fname: data0 #$i\n";
		close FH;
	}

	my $bt = $module->new( @filenames );
	cmp_bag( [keys %{$bt->{files}}], \@filenames, 'Files are correct');

	my $res = $bt->tail(1);
	ok(!$res, "Nothing read, ofcourse");

	my $fname = $filenames[1];
	open FH, ">>$fname";
	my $data = "$fname:abc\nxyz\n";
	print FH $data;
	close FH;
	my $ph = { $fname => $data };

	unlink $fname;

	$res = $bt->tail(9);
	is(scalar(keys %$res), 1, "We have data");
	cmp_deeply($res, $ph, "data is good");
	unlink($_) foreach (@filenames);
}

sub rename_01 { #4
	my ($module) = @_;

	diag("--- running rename_01 for $module");

	my $numfiles = 3;
	my @filenames = ();

	for(my $i=0; $i<$numfiles; $i++) {
		my $fname = tmpnam();
		push @filenames, $fname;
		open FH, ">>$fname";
		print FH "$fname: data0 #$i\n";
		close FH;
	}

	my $bt = $module->new( @filenames );
	cmp_bag( [keys %{$bt->{files}}], \@filenames, 'Files are correct');

	my $res = $bt->tail(1);
	ok(!$res, "Nothing read, ofcourse");

	my $fname = $filenames[1];
	open FH, ">>$fname";
	my $data = "$fname:abc\nxyz\n";
	print FH $data;
	close FH;
	my $ph = { $fname => $data };

	rename $fname, "$fname.xyz";
	push @filenames, "$fname.xyz";
	$res = $bt->tail(9);
	is(scalar(keys %$res), 1, "We have data");
	cmp_deeply($res, $ph, "data is good");

	unlink($_) foreach (@filenames);
}



for my $module ( @modules ) {
	SKIP: {
		skip "Not testing $module", (8) if ( ($module eq 'BOIA::Tail::KQueue' && $os ne 'bsd') ||
     						     ($module eq 'BOIA::Tail::Inotify' && $os ne 'linux') );

		basic_01($module);
	};

	SKIP: {
		skip "Not testing $module", (4+4) if ( ($module eq 'BOIA::Tail::KQueue' && $os ne 'bsd') ||
     						       ($module eq 'BOIA::Tail::Inotify' && $os ne 'linux') || 
						       $module eq 'BOIA::Tail::Generic' || $os eq '');

		delete_01($module);
		rename_01($module);
	};
}


