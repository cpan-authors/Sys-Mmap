#! perl

use strict;
use warnings;

use Test::More tests => 9;

use Sys::Mmap;
use Fcntl qw(O_WRONLY O_CREAT O_TRUNC O_RDONLY O_RDWR);

my $temp_file = "remmap.tmp";

sub create_test_file {
    my ($content) = @_;
    sysopen(my $fh, $temp_file, O_WRONLY|O_CREAT|O_TRUNC) or die "$temp_file: $!\n";
    print $fh $content;
    close $fh;
}

# ---- Re-mmap: mapping a variable that is already mmap'd ----

{
    create_test_file("A" x 8192);

    my $data;
    sysopen(my $fh, $temp_file, O_RDONLY) or die "$temp_file: $!\n";
    mmap($data, 4096, PROT_READ, MAP_SHARED, $fh);
    close $fh;

    is(length($data), 4096, "first mmap: correct length");
    is(substr($data, 0, 1), "A", "first mmap: correct content");

    # Re-mmap the same variable with a different length
    sysopen(my $fh2, $temp_file, O_RDONLY) or die "$temp_file: $!\n";
    mmap($data, 8192, PROT_READ, MAP_SHARED, $fh2);
    close $fh2;

    is(length($data), 8192, "re-mmap: new length is correct");
    is($data, "A" x 8192, "re-mmap: sees new mapping content");

    munmap($data);
    pass("re-mmap: munmap succeeds after re-mapping");
}

# ---- Re-mmap: read-only then writable ----
# Ensures the read-only flag from the first mapping is cleared

{
    create_test_file("B" x 8192);

    my $data;

    # First mapping: read-only
    sysopen(my $fh, $temp_file, O_RDONLY) or die "$temp_file: $!\n";
    mmap($data, 4096, PROT_READ, MAP_SHARED, $fh);
    close $fh;

    is(length($data), 4096, "ro-then-rw: read-only mapping works");

    # Re-mmap as writable — must not fail due to stale SvREADONLY
    sysopen(my $fh2, $temp_file, O_RDWR) or die "$temp_file: $!\n";
    mmap($data, 4096, PROT_READ|PROT_WRITE, MAP_SHARED, $fh2);
    close $fh2;

    is(length($data), 4096, "ro-then-rw: writable mapping works");

    # Writing should succeed
    substr($data, 0, 4) = "TEST";
    is(substr($data, 0, 4), "TEST", "ro-then-rw: can write to re-mapped variable");

    munmap($data);
}

# ---- Re-mmap: scope exit cleanup with stacked magic ----
# The old magic should not cause a double-munmap crash

{
    create_test_file("C" x 4096);

    {
        my $data;
        sysopen(my $fh, $temp_file, O_RDONLY) or die "$temp_file: $!\n";
        mmap($data, 4096, PROT_READ, MAP_SHARED, $fh);
        close $fh;

        sysopen(my $fh2, $temp_file, O_RDONLY) or die "$temp_file: $!\n";
        mmap($data, 4096, PROT_READ, MAP_SHARED, $fh2);
        close $fh2;

        # $data goes out of scope — DESTROY fires with stacked magic entries
    }
    pass("re-mmap scope exit: no crash from stacked magic cleanup");
}

unlink($temp_file);
