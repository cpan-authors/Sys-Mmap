#! perl

use strict;
use warnings;

use Test::More;

use Sys::Mmap;

# These constants must always be available on any POSIX platform
my @required = qw(MAP_SHARED MAP_PRIVATE PROT_READ PROT_WRITE PROT_EXEC PROT_NONE);

for my $name (@required) {
    my $val = eval "Sys::Mmap::$name()";
    ok(defined $val, "$name is defined");
    like("$val", qr/^\d+\z/, "$name is an integer (no decimal point)");
}

# Verify constants can be used in bitwise operations without warnings
{
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, $_[0] };

    my $rw = PROT_READ | PROT_WRITE;
    ok($rw > 0, "PROT_READ | PROT_WRITE produces a positive value");

    my $shared_anon = MAP_SHARED | MAP_ANON;
    ok($shared_anon > 0, "MAP_SHARED | MAP_ANON produces a positive value");

    is(scalar @warnings, 0, "no warnings from bitwise operations on constants");
}

# Optional constants that may not exist on all platforms
my @optional = qw(MAP_ANON MAP_ANONYMOUS MAP_FILE MAP_LOCKED MAP_NORESERVE
                   MAP_POPULATE MAP_HUGETLB MAP_HUGE_2MB MAP_HUGE_1GB);

for my $name (@optional) {
    my $val = eval "Sys::Mmap::$name()";
    if (defined $val) {
        like("$val", qr/^\d+\z/, "$name is an integer (no decimal point)");
    } else {
        pass("$name not available on this platform (ok)");
    }
}

done_testing;
