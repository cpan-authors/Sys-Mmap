#! perl

use strict;
use warnings;

use Test::More;
use Sys::Mmap;
use Fcntl qw(O_RDWR O_CREAT O_TRUNC O_RDONLY);

my $temp_file = "tied_sync.tmp";

sub create_test_file {
    my ($size) = @_;
    sysopen(my $fh, $temp_file, O_RDWR|O_CREAT|O_TRUNC) or die "$temp_file: $!\n";
    my $content = "A" x $size;
    print $fh $content;
    close $fh;
    return $content;
}

# sync() with default flags (MS_SYNC)
{
    create_test_file(4096);

    my $obj = Sys::Mmap->new(my $var, 4096, $temp_file);
    ok(defined $obj, "sync default: new() succeeded");

    substr($var, 0, 5) = "Hello";
    is(substr($var, 0, 5), "Hello", "sync default: STORE wrote data");

    my $ok = eval { $obj->sync; 1 };
    ok($ok, "sync default: sync() succeeded") or diag $@;

    # Verify data persisted to disk
    sysopen(my $fh, $temp_file, O_RDONLY) or die "$temp_file: $!\n";
    my $buf;
    sysread($fh, $buf, 5);
    close $fh;
    is($buf, "Hello", "sync default: data flushed to file");
}

# sync(MS_ASYNC)
{
    create_test_file(4096);

    my $obj = Sys::Mmap->new(my $var, 4096, $temp_file);
    ok(defined $obj, "sync async: new() succeeded");

    substr($var, 0, 4) = "Test";

    my $ok = eval { $obj->sync(MS_ASYNC); 1 };
    ok($ok, "sync async: sync(MS_ASYNC) succeeded") or diag $@;
}

# sync() on anonymous mapping (no file, just verify no crash)
{
    my $obj = Sys::Mmap->new(my $var, 4096);
    ok(defined $obj, "sync anon: new() with anonymous memory succeeded");

    substr($var, 0, 4) = "Test";

    # msync on MAP_ANON|MAP_SHARED is implementation-defined but should not crash
    my $ok = eval { $obj->sync; 1 };
    # Some kernels reject msync on anonymous mappings — both outcomes are acceptable
    ok(1, "sync anon: sync() did not crash (success=$ok)");
}

# Variable still usable after sync
{
    create_test_file(4096);

    my $obj = Sys::Mmap->new(my $var, 4096, $temp_file);
    substr($var, 0, 3) = "One";
    $obj->sync;

    substr($var, 3, 3) = "Two";
    $obj->sync;

    is(substr($var, 0, 6), "OneTwo", "post-sync: mapping still usable after multiple syncs");
}

unlink($temp_file);
done_testing;
