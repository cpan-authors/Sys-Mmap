#! perl

use strict;
use warnings;

use Test::More tests => 12;

use Sys::Mmap;
use Fcntl qw(O_WRONLY O_CREAT O_TRUNC O_RDONLY O_RDWR);

my $temp_file = "msync.tmp";
my $file_size = 8192;

# Create a test file with known content
sub create_test_file {
    my ($size) = @_;
    sysopen(my $fh, $temp_file, O_WRONLY|O_CREAT|O_TRUNC) or die "$temp_file: $!\n";
    my $content = "A" x $size;
    print $fh $content;
    close $fh;
    return $content;
}

# ---- MS_* constants exist ----

{
    ok(defined MS_SYNC,       "MS_SYNC is defined");
    ok(defined MS_ASYNC,      "MS_ASYNC is defined");
    ok(defined MS_INVALIDATE, "MS_INVALIDATE is defined");
}

# ---- msync on a writable file mapping ----

{
    create_test_file($file_size);

    my $data;
    sysopen(my $fh, $temp_file, O_RDWR) or die "$temp_file: $!\n";
    mmap($data, 0, PROT_READ|PROT_WRITE, MAP_SHARED, $fh);
    close $fh;

    # Modify the mapped region
    substr($data, 0, 5) = "Hello";

    # msync with default flags (MS_SYNC)
    my $ret = msync($data);
    is($ret, 1, "msync with default flags returns 1");

    # Verify the data was flushed by reading the file directly
    sysopen(my $fh2, $temp_file, O_RDONLY) or die "$temp_file: $!\n";
    my $on_disk;
    sysread($fh2, $on_disk, $file_size);
    close $fh2;
    is(substr($on_disk, 0, 5), "Hello", "msync flushed data to disk");

    # msync with explicit MS_SYNC
    substr($data, 5, 5) = "World";
    $ret = msync($data, MS_SYNC);
    is($ret, 1, "msync with MS_SYNC returns 1");

    # msync with MS_ASYNC
    substr($data, 10, 1) = "!";
    $ret = msync($data, MS_ASYNC);
    is($ret, 1, "msync with MS_ASYNC returns 1");

    munmap($data);
}

# ---- msync on a read-only mapping ----

{
    create_test_file($file_size);

    my $data;
    sysopen(my $fh, $temp_file, O_RDONLY) or die "$temp_file: $!\n";
    mmap($data, 0, PROT_READ, MAP_SHARED, $fh);
    close $fh;

    my $ret = msync($data, MS_SYNC);
    is($ret, 1, "msync on read-only mapping succeeds");

    munmap($data);
}

# ---- msync error cases ----

{
    my $undef_var;
    eval { msync($undef_var) };
    like($@, qr/msync: variable is not defined/, "msync on undef croaks");
}

{
    my $str = "not mmap'd";
    eval { msync($str) };
    like($@, qr/msync:/, "msync on plain string croaks");
}

# ---- msync with non-zero offset mapping ----

{
    create_test_file($file_size);

    my $data;
    sysopen(my $fh, $temp_file, O_RDWR) or die "$temp_file: $!\n";
    mmap($data, 4096, PROT_READ|PROT_WRITE, MAP_SHARED, $fh, 256);
    close $fh;

    substr($data, 0, 4) = "TEST";
    my $ret = msync($data, MS_SYNC);
    is($ret, 1, "msync with non-zero offset mapping returns 1");

    # Verify it was flushed
    sysopen(my $fh2, $temp_file, O_RDONLY) or die "$temp_file: $!\n";
    my $on_disk;
    sysread($fh2, $on_disk, $file_size);
    close $fh2;
    is(substr($on_disk, 256, 4), "TEST", "msync with offset flushed data correctly");

    munmap($data);
}

# Cleanup
unlink($temp_file);
