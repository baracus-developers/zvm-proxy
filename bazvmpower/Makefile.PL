use strict;
use warnings;
use ExtUtils::MakeMaker;

my @scripts = qw(bazvmpower.pl vmcp.pl);

WriteMakefile(
    NAME                => 'zVMPower',
    AUTHOR              => q{YOUR NAME <youremail@example.com>},
    VERSION_FROM        => 'lib/Baracus/zVMPower.pm',
    ABSTRACT            => 'YOUR APPLICATION ABSTRACT',
    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'perl')
      : ()),
    EXE_FILES           => [ map { "script/$_" } @scripts ],
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
        'YAML'       => 0,
        'Dancer'     => 1.1805,
    },
    dist                => { COMPRESS => 'bzip2 -9f', SUFFIX => 'bz2', },
    clean               => { FILES => 'logs/*.log' },
);
