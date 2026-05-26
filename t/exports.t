#! perl

use strict;
use warnings;

use Test::More;

use Sys::Mmap;

# Verify that all exported constants are callable and return integers.
# The MS_* constants were added to @EXPORT but had no dedicated test
# coverage, so this validates the full export list.

my @exported_functions = qw(mmap munmap msync);

my @required_constants = qw(
    MAP_SHARED MAP_PRIVATE
    PROT_READ PROT_WRITE PROT_EXEC PROT_NONE
    MS_ASYNC MS_SYNC MS_INVALIDATE
);

my @optional_constants = qw(
    MAP_ANON MAP_ANONYMOUS MAP_FILE MAP_LOCKED MAP_NORESERVE
    MAP_POPULATE MAP_HUGETLB MAP_HUGE_2MB MAP_HUGE_1GB
);

for my $func (@exported_functions) {
    ok(defined &{"main::$func"}, "$func is exported and callable");
}

for my $name (@required_constants) {
    my $val = eval { no strict 'refs'; &{"main::$name"}() };
    ok(defined $val, "$name is defined") or diag("Error: $@");
    like("$val", qr/^\d+\z/, "$name is an integer") if defined $val;
}

for my $name (@optional_constants) {
    my $val = eval { no strict 'refs'; &{"main::$name"}() };
    if (defined $val) {
        like("$val", qr/^\d+\z/, "$name is an integer");
    } else {
        pass("$name not available on this platform (ok)");
    }
}

# MS_* constants should be usable in expressions without warnings
{
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, $_[0] };

    my $sync_flags = MS_SYNC | MS_INVALIDATE;
    ok($sync_flags > 0, "MS_SYNC | MS_INVALIDATE produces a positive value");

    is(scalar @warnings, 0, "no warnings from bitwise operations on MS_* constants");
}

# Undefined constants should croak
{
    my $val = eval { Sys::Mmap::DOES_NOT_EXIST() };
    ok(!defined $val, "undefined constant returns undef (via eval)");
    like($@, qr/not defined/, "undefined constant produces an error");
}

done_testing;
