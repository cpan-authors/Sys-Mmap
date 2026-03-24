use strict;
use warnings;
use ExtUtils::MakeMaker;

my %test_requires = (
    'Test::More' => 0,
    'Errno'      => 0,
);

my %prereq_pm = (
    ($] >= 5.006 ? ('XSLoader' => 0) : ()),
    'DynaLoader' => 0,
);

# Older EUMM doesn't support TEST_REQUIRES; merge into PREREQ_PM
if ($ExtUtils::MakeMaker::VERSION < 6.64) {
    %prereq_pm = (%prereq_pm, %test_requires);
}

WriteMakefile(
    NAME             => 'Sys::Mmap',
    AUTHOR           => 'Scott Walters <swalters@cpan.org>',
    VERSION_FROM     => 'Mmap.pm',
    ABSTRACT_FROM    => 'Mmap.pm',
    PL_FILES         => {},
    MIN_PERL_VERSION => '5.008',
    LICENSE          => 'perl',
    PREREQ_PM        => \%prereq_pm,
    ($ExtUtils::MakeMaker::VERSION >= 6.64 ? (TEST_REQUIRES => \%test_requires) : ()),
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean => { FILES => 'Sys-Mmap-*' },
    META_MERGE => {
        'meta-spec' => { version => 2 },
        resources => {
            repository => {
                type => 'git',
                url  => 'https://github.com/cpan-authors/Sys-Mmap.git',
                web  => 'https://github.com/cpan-authors/Sys-Mmap',
            },
            bugtracker => {
                web => 'https://github.com/cpan-authors/Sys-Mmap/issues',
            },
        },
        no_index => {
            directory => ['t', 'xt'],
        },
    },
);
