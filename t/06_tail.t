use Test::More tests => 1+4*(8+4+4+4+6);
use warnings;
use strict;

use Test::Deep;
use File::Temp qw( :POSIX );

use lib './lib';

use BOIA::Log;
use BOIA::Tail;
use BOIA::Tail::Generic;

my $syslog = [];
no warnings 'redefine';
local *BOIA::Log::write_syslog = sub { my ($c, $l, $s) = @_; push @$syslog, $s };
use warnings 'redefine';
BOIA::Log->open( { level => LOG_DEBUG, syslog => 1 });


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

sub make_temp_files {
	my ($numfiles) = @_;

	$numfiles ||= 3;
	my @filenames = ();

	for(my $i=0; $i<$numfiles; $i++) {
		my $fname = tmpnam();
		push @filenames, $fname;
		open FH, ">>$fname";
		print FH "$fname: data0 #$i\n";
		close FH;
	}
	return @filenames;
}

sub basic_00 { #1

	diag("--- running basic_00");

	my $bt = BOIA::Tail->new( qw( /etc/passwd /etc/group ) );

	my $class = ref($bt);

	if ($os eq 'bsd') {
		is($class, 'BOIA::Tail::KQueue', 'OS is BSD, so BOIA::Tail returns BOIA::Tail::KQueue');
	} elsif ($os eq 'linux') {
		is($class, 'BOIA::Tail::Inotify', 'OS is Linux, so BOIA::Tail returns BOIA::Tail::Inotify');
	} else {
		is($class, 'BOIA::Tail::Generic', 'BOIA::Tail returns BOIA::Tail::Generic');
	}
}

sub basic_01 { # 8
	my ($module) = @_;

	diag("--- running basic_01 for $module");

	my @filenames = make_temp_files(3);

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

	my @filenames = make_temp_files(3);

	my $bt = $module->new( @filenames );
	cmp_bag( [keys %{$bt->{files}}], \@filenames, 'Files are correct');

#$syslog = [];
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
#use Data::Dumper;
#print STDERR Dumper($syslog);
}

sub rename_01 { #4
	my ($module) = @_;

	diag("--- running rename_01 for $module");

	my @filenames = make_temp_files(3);

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

sub rename_02 { #4
	my ($module) = @_;

	diag("--- running rename_02 for $module");

	my @filenames = make_temp_files(3);

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

	#recreate
	open FH, ">$fname";
	print FH "newdata\n";
	close FH;
	$ph = { $fname => $data."newdata\n" };

	$res = $bt->tail(9);
	is(scalar(keys %$res), 1, "We have data");
	cmp_deeply($res, $ph, "data is good");

	unlink($_) foreach (@filenames);
}

sub rename_03 { #6
	my ($module) = @_;

	diag("--- running rename_03 for $module");

	my @filenames = make_temp_files(3);

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

	#recreate
	open FH, ">$fname";
	print FH "newdata\n";
	close FH;

	$bt->set_files(@filenames);

	open FH, ">>$fname";
	print FH "newdata2\n";
	close FH;
	$ph = { $fname => "newdata\nnewdata2\n" };

	$res = $bt->tail(9);
	is(scalar(keys %$res), 1, "We have data");
	cmp_deeply($res, $ph, "data is good");

	unlink($_) foreach (@filenames);
}

basic_00();

for my $module ( @modules ) {
	SKIP: {
		skip "Not testing $module", (8) if ( ($module eq 'BOIA::Tail::KQueue' && $os ne 'bsd') ||
     						     ($module eq 'BOIA::Tail::Inotify' && $os ne 'linux') );

		basic_01($module);
	};

	SKIP: {
		skip "Not testing $module", (4+4+4+6) if ( ($module eq 'BOIA::Tail::KQueue' && $os ne 'bsd') ||
     						           ($module eq 'BOIA::Tail::Inotify' && $os ne 'linux') || 
						           $module eq 'BOIA::Tail::Generic' || $os eq '');

		delete_01($module);
		rename_01($module);
		rename_02($module);
		rename_03($module);
	};
}

