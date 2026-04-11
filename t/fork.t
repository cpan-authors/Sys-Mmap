#! perl

use strict;
use warnings;

use Test::More;
use Sys::Mmap;
use Fcntl qw(O_RDONLY O_RDWR O_CREAT O_TRUNC);
use POSIX qw(_exit);

# Fork tests require a working fork()
plan skip_all => "fork() not available on $^O" if $^O eq 'MSWin32';

plan tests => 12;

my $temp_file = "fork.tmp";

sub create_test_file {
    my ($size, $pattern) = @_;
    $pattern = "A" unless defined $pattern;
    sysopen(my $fh, $temp_file, O_RDWR|O_CREAT|O_TRUNC) or die "$temp_file: $!\n";
    my $content = $pattern x $size;
    print $fh $content;
    close $fh;
    return $content;
}

# ---- MAP_SHARED file: child writes, parent sees ----

{
    create_test_file(4096);

    my $data;
    sysopen(my $fh, $temp_file, O_RDWR) or die "$temp_file: $!\n";
    mmap($data, 4096, PROT_READ|PROT_WRITE, MAP_SHARED, $fh);
    close $fh;

    my $pid = fork();
    die "fork failed: $!" unless defined $pid;

    if ($pid == 0) {
        substr($data, 0, 5) = "CHILD";
        munmap($data);
        _exit(0);  # avoid END blocks and global destruction
    }

    waitpid($pid, 0);
    is($? >> 8, 0, "MAP_SHARED file: child exited cleanly");
    is(substr($data, 0, 5), "CHILD", "MAP_SHARED file: child's write visible in parent");

    munmap($data);
}

# ---- MAP_PRIVATE file: child writes, parent does NOT see ----

{
    create_test_file(4096);

    my $data;
    sysopen(my $fh, $temp_file, O_RDWR) or die "$temp_file: $!\n";
    mmap($data, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE, $fh);
    close $fh;

    my $pid = fork();
    die "fork failed: $!" unless defined $pid;

    if ($pid == 0) {
        substr($data, 0, 7) = "PRIVATE";
        munmap($data);
        _exit(0);
    }

    waitpid($pid, 0);
    is($? >> 8, 0, "MAP_PRIVATE file: child exited cleanly");
    is(substr($data, 0, 7), "A" x 7, "MAP_PRIVATE file: child's write NOT visible in parent");

    munmap($data);
}

# ---- MAP_SHARED|MAP_ANON: anonymous shared memory across fork ----

{
    my $data;
    mmap($data, 4096, PROT_READ|PROT_WRITE, MAP_SHARED|MAP_ANON, *STDOUT);

    is($data, "\0" x 4096, "MAP_ANON shared: initial memory is zeroed");

    # Parent writes a marker before fork
    substr($data, 0, 6) = "PARENT";

    my $pid = fork();
    die "fork failed: $!" unless defined $pid;

    if ($pid == 0) {
        # Child: verify parent's write, then write own marker
        my $saw_parent = (substr($data, 0, 6) eq "PARENT") ? 1 : 0;
        substr($data, 100, 1) = chr($saw_parent);  # signal to parent
        substr($data, 6, 5) = "CHILD";
        munmap($data);
        _exit(0);
    }

    waitpid($pid, 0);
    is($? >> 8, 0, "MAP_ANON shared: child exited cleanly");
    is(substr($data, 6, 5), "CHILD", "MAP_ANON shared: child's write visible in parent");
    is(ord(substr($data, 100, 1)), 1, "MAP_ANON shared: child saw parent's write");

    munmap($data);
}

# ---- DESTROY in child does not break parent's mapping ----
# Child lets the variable go out of scope (implicit DESTROY) instead
# of calling munmap().  Since munmap() only affects the calling process's
# address space, the parent's mapping should remain intact.

{
    my $data;
    mmap($data, 4096, PROT_READ|PROT_WRITE, MAP_SHARED|MAP_ANON, *STDOUT);
    substr($data, 0, 4) = "SAFE";

    my $pid = fork();
    die "fork failed: $!" unless defined $pid;

    if ($pid == 0) {
        # Do NOT munmap — let DESTROY handle it during exit
        substr($data, 4, 5) = "CHILD";
        _exit(0);
    }

    waitpid($pid, 0);
    is($? >> 8, 0, "DESTROY in child: child exited cleanly");

    # Parent's mapping should still be valid after child's DESTROY
    my $ok = eval { substr($data, 0, 9) eq "SAFECHILD" };
    ok($ok, "DESTROY in child: parent's mapping still valid");

    munmap($data);
}

# ---- Multiple children writing to different offsets ----

{
    my $data;
    mmap($data, 4096, PROT_READ|PROT_WRITE, MAP_SHARED|MAP_ANON, *STDOUT);

    my $n_children = 4;
    my @pids;

    for my $i (0 .. $n_children - 1) {
        my $pid = fork();
        die "fork failed: $!" unless defined $pid;

        if ($pid == 0) {
            # Each child writes its index at a unique offset
            substr($data, $i * 100, 1) = chr(ord("0") + $i);
            munmap($data);
            _exit(0);
        }
        push @pids, $pid;
    }

    waitpid($_, 0) for @pids;

    my $all_ok = 1;
    for my $i (0 .. $n_children - 1) {
        $all_ok = 0 unless substr($data, $i * 100, 1) eq chr(ord("0") + $i);
    }
    ok($all_ok, "multi-child: all children's writes visible in parent");

    munmap($data);
}

# ---- Verify file-backed MAP_SHARED persists to disk after child writes ----

{
    create_test_file(4096);

    my $data;
    sysopen(my $fh, $temp_file, O_RDWR) or die "$temp_file: $!\n";
    mmap($data, 4096, PROT_READ|PROT_WRITE, MAP_SHARED, $fh);
    close $fh;

    my $pid = fork();
    die "fork failed: $!" unless defined $pid;

    if ($pid == 0) {
        substr($data, 0, 4) = "DISK";
        msync($data, MS_SYNC);
        munmap($data);
        _exit(0);
    }

    waitpid($pid, 0);
    munmap($data);

    # Read the file directly — the child's write should be on disk
    sysopen(my $fh2, $temp_file, O_RDONLY) or die "$temp_file: $!\n";
    my $on_disk;
    sysread($fh2, $on_disk, 4096);
    close $fh2;
    is(substr($on_disk, 0, 4), "DISK", "MAP_SHARED file: child's write persisted to disk");
}

# Cleanup
unlink($temp_file);
