#! perl

use strict;
use warnings;

use Test::More tests => 6;

use Sys::Mmap;
use Fcntl qw(O_WRONLY O_CREAT O_TRUNC O_RDONLY);

my $temp_file = "offset.tmp";
my $file_size = 8192;

# Create a file large enough to map with an offset
sysopen(FOO, $temp_file, O_WRONLY|O_CREAT|O_TRUNC) or die "$temp_file: $!\n";
print FOO "A" x $file_size;
close FOO;

# Test 1: mmap with non-zero offset and explicit munmap
{
    my $data;
    sysopen(FOO, $temp_file, O_RDONLY) or die "$temp_file: $!\n";
    mmap($data, 256, PROT_READ, MAP_SHARED, FOO, 256);
    close FOO;
    is(length($data), 256, "mmap with offset returns correct length");
    is($data, "A" x 256, "mmap with offset returns correct data");
    munmap($data);
}

# Test 2: mmap with non-zero offset, DESTROY cleanup (no explicit munmap)
# This is the crash from GitHub issue #1 - segfault on cleanup when offset != 0
{
    my $data;
    sysopen(FOO, $temp_file, O_RDONLY) or die "$temp_file: $!\n";
    mmap($data, 256, PROT_READ, MAP_SHARED, FOO, 256);
    close FOO;
    is(length($data), 256, "mmap with offset (DESTROY path) returns correct length");
    # $data goes out of scope here - DESTROY is called instead of explicit munmap
    # Before the fix, this would segfault
}

pass("Survived DESTROY with non-zero offset (no segfault)");

# Test 3: large offset (> 2^31) correctly rejected on small file
# Before the fix, atoi() would truncate offsets > 2GB, potentially wrapping
# to a small positive value and silently mapping the wrong region.
SKIP: {
    use Config;
    skip "off_t is 32-bit on this platform", 2
        unless ($Config{lseeksize} || 0) >= 8;

    my $big_offset = 2**31 + 4096;

    my $data;
    sysopen(FOO, $temp_file, O_RDONLY) or die "$temp_file: $!\n";
    my $ok = eval { mmap($data, 0, PROT_READ, MAP_SHARED, FOO, $big_offset); 1 };
    close FOO;
    is($ok, undef, "large offset (> 2^31) on small file croaks");
    like($@, qr/offset.*beyond end of file/i, "large offset error message is correct");
}

unlink($temp_file);
