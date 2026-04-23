#! perl

use strict;
use warnings;

use Test::More tests => 18;

use Sys::Mmap;
use Fcntl qw(O_WRONLY O_CREAT O_TRUNC O_RDONLY O_RDWR);

my $temp_file = "map_private.tmp";

sub create_test_file {
    my ($size, $pattern) = @_;
    $pattern = "X" unless defined $pattern;
    sysopen(my $fh, $temp_file, O_WRONLY|O_CREAT|O_TRUNC) or die "$temp_file: $!\n";
    my $content = $pattern x $size;
    $content = substr($content, 0, $size);
    print $fh $content;
    close $fh;
    return $content;
}

sub read_file {
    sysopen(my $fh, $temp_file, O_RDONLY) or die "$temp_file: $!\n";
    my $data;
    sysread($fh, $data, -s $temp_file);
    close $fh;
    return $data;
}

# ---- MAP_PRIVATE copy-on-write: writes don't reach the file ----

{
    my $original = create_test_file(4096);

    my $data;
    sysopen(my $fh, $temp_file, O_RDWR) or die "$temp_file: $!\n";
    mmap($data, 0, PROT_READ|PROT_WRITE, MAP_PRIVATE, $fh);
    close $fh;

    is($data, $original, "MAP_PRIVATE: initial content matches file");
    is(length($data), 4096, "MAP_PRIVATE: mapping has correct length");

    # Write to the private mapping
    substr($data, 0, 7) = "PRIVATE";
    is(substr($data, 0, 7), "PRIVATE", "MAP_PRIVATE: write visible in mapping");

    # Verify the file on disk is unchanged (copy-on-write semantics)
    my $on_disk = read_file();
    is($on_disk, $original, "MAP_PRIVATE: file on disk is unchanged after write");

    munmap($data);
}

# ---- MAP_PRIVATE read-only: can map without write permission ----

{
    my $original = create_test_file(4096);

    my $data;
    sysopen(my $fh, $temp_file, O_RDONLY) or die "$temp_file: $!\n";
    mmap($data, 0, PROT_READ, MAP_PRIVATE, $fh);
    close $fh;

    is($data, $original, "MAP_PRIVATE PROT_READ: content matches file");
    ok(SvREADONLY($data), "MAP_PRIVATE PROT_READ: variable is read-only");

    munmap($data);
}

# ---- Two MAP_PRIVATE mappings of the same file are independent ----

{
    my $original = create_test_file(4096);

    my ($data1, $data2);
    sysopen(my $fh1, $temp_file, O_RDWR) or die "$temp_file: $!\n";
    sysopen(my $fh2, $temp_file, O_RDWR) or die "$temp_file: $!\n";
    mmap($data1, 0, PROT_READ|PROT_WRITE, MAP_PRIVATE, $fh1);
    mmap($data2, 0, PROT_READ|PROT_WRITE, MAP_PRIVATE, $fh2);
    close $fh1;
    close $fh2;

    # Both start with same content
    is($data1, $data2, "MAP_PRIVATE x2: both mappings start identical");

    # Write different data to each
    substr($data1, 0, 5) = "AAAAA";
    substr($data2, 0, 5) = "BBBBB";

    is(substr($data1, 0, 5), "AAAAA", "MAP_PRIVATE x2: first mapping has its own data");
    is(substr($data2, 0, 5), "BBBBB", "MAP_PRIVATE x2: second mapping has its own data");

    # Original file untouched by either
    my $on_disk = read_file();
    is($on_disk, $original, "MAP_PRIVATE x2: file unchanged after both writes");

    munmap($data1);
    munmap($data2);
}

# ---- MAP_PRIVATE|MAP_ANON: private anonymous memory ----

SKIP: {
    skip "MAP_ANON not available", 3 unless eval { MAP_ANON(); 1 };

    my $data;
    mmap($data, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANON, *STDOUT);
    ok(defined $data, "MAP_PRIVATE|MAP_ANON: mmap succeeds");
    is(length($data), 4096, "MAP_PRIVATE|MAP_ANON: correct length");

    # Private anonymous memory should be zero-filled
    is($data, "\0" x 4096, "MAP_PRIVATE|MAP_ANON: memory is zero-filled");

    munmap($data);
}

# ---- MAP_PRIVATE with explicit offset ----

{
    my $original = create_test_file(8192, "P");
    my $offset = 4096;

    my $data;
    sysopen(my $fh, $temp_file, O_RDWR) or die "$temp_file: $!\n";
    mmap($data, 0, PROT_READ|PROT_WRITE, MAP_PRIVATE, $fh, $offset);
    close $fh;

    is(length($data), 8192 - $offset, "MAP_PRIVATE offset: correct length");
    is($data, substr($original, $offset), "MAP_PRIVATE offset: content matches from offset");

    # Write to the private mapping
    substr($data, 0, 6) = "OFFSET";
    is(substr($data, 0, 6), "OFFSET", "MAP_PRIVATE offset: write visible in mapping");

    # Original file unchanged
    my $on_disk = read_file();
    is($on_disk, $original, "MAP_PRIVATE offset: file unchanged after write");

    munmap($data);
}

# ---- MAP_PRIVATE DESTROY cleanup via scope exit ----

{
    create_test_file(4096);
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, $_[0] };

    {
        my $data;
        sysopen(my $fh, $temp_file, O_RDWR) or die "$temp_file: $!\n";
        mmap($data, 0, PROT_READ|PROT_WRITE, MAP_PRIVATE, $fh);
        close $fh;
        substr($data, 0, 4) = "GONE";
        # $data goes out of scope — DESTROY should clean up
    }

    my @bad = grep { /munmap|mmap|DESTROY/ } @warnings;
    is(scalar @bad, 0, "MAP_PRIVATE DESTROY: no warnings during cleanup");
}

# Perl's SvREADONLY check for the PROT_READ test
sub SvREADONLY {
    return !eval { substr($_[0], 0, 1) = "Z"; 1 };
}

# Cleanup
unlink($temp_file);
