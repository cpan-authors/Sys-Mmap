#! perl

use strict;
use warnings;

use Test::More tests => 11;

use Sys::Mmap;
use Fcntl qw(O_WRONLY O_CREAT O_TRUNC O_RDONLY O_RDWR);

my $temp_file = "mlock.tmp";
my $file_size = 8192;

sub create_test_file {
    my ($size) = @_;
    sysopen(my $fh, $temp_file, O_WRONLY|O_CREAT|O_TRUNC) or die "$temp_file: $!\n";
    print $fh ("A" x $size);
    close $fh;
}

# ---- mlock/munlock on a writable file mapping ----

{
    create_test_file($file_size);

    my $data;
    sysopen(my $fh, $temp_file, O_RDWR) or die "$temp_file: $!\n";
    mmap($data, 0, PROT_READ|PROT_WRITE, MAP_SHARED, $fh);
    close $fh;

    my $ret = mlock($data);
    is($ret, 1, "mlock on writable mapping returns 1");

    # Data still accessible after locking
    is(substr($data, 0, 1), "A", "mmap'd data accessible after mlock");

    # Can still write to locked pages
    substr($data, 0, 5) = "Hello";
    is(substr($data, 0, 5), "Hello", "can write to mlock'd region");

    $ret = munlock($data);
    is($ret, 1, "munlock returns 1");

    # Data still accessible after unlocking
    is(substr($data, 0, 5), "Hello", "data intact after munlock");

    munmap($data);
}

# ---- mlock on a read-only mapping ----

{
    create_test_file($file_size);

    my $data;
    sysopen(my $fh, $temp_file, O_RDONLY) or die "$temp_file: $!\n";
    mmap($data, 0, PROT_READ, MAP_SHARED, $fh);
    close $fh;

    my $ret = mlock($data);
    is($ret, 1, "mlock on read-only mapping succeeds");

    $ret = munlock($data);
    is($ret, 1, "munlock on read-only mapping succeeds");

    munmap($data);
}

# ---- mlock with non-zero offset mapping ----

{
    create_test_file($file_size);

    my $data;
    sysopen(my $fh, $temp_file, O_RDWR) or die "$temp_file: $!\n";
    mmap($data, 4096, PROT_READ|PROT_WRITE, MAP_SHARED, $fh, 256);
    close $fh;

    my $ret = mlock($data);
    is($ret, 1, "mlock with non-zero offset mapping returns 1");

    $ret = munlock($data);
    is($ret, 1, "munlock with non-zero offset mapping returns 1");

    munmap($data);
}

# ---- error cases ----

{
    my $undef_var;
    eval { mlock($undef_var) };
    like($@, qr/mlock: variable is not defined/, "mlock on undef croaks");
}

{
    my $str = "not mmap'd";
    eval { mlock($str) };
    like($@, qr/mlock:/, "mlock on plain string croaks");
}

# Cleanup
unlink($temp_file);
