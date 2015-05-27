use ExtUtils::MakeMaker;

WriteMakefile(
	NAME            => 'BOIA',
	VERSION_FROM    => 'lib/BOIA.pm',
	EXE_FILES	=> [qw( script/boia )],
);

