#! perl

use strict;
use warnings;

use Test::More;

BEGIN {
    eval { require threads; threads->import(); 1 }
        or plan skip_all => 'threads not available';
}

use Sys::Mmap;
use Fcntl qw(O_WRONLY O_CREAT O_TRUNC O_RDONLY O_RDWR);

plan tests => 7;

my $temp_file = "threads.tmp";
my $content = "THREAD_TEST_DATA" x 256;

sysopen(my $fh_w, $temp_file, O_WRONLY|O_CREAT|O_TRUNC) or die "$temp_file: $!\n";
print $fh_w $content;
close $fh_w;

# Test 1-2: thread clone of read-only mmap'd variable
{
    my $mapped;
    sysopen(my $fh, $temp_file, O_RDONLY) or die "$temp_file: $!\n";
    mmap($mapped, 0, PROT_READ, MAP_SHARED, $fh);
    close $fh;

    my $thr = threads->create(sub {
        return length($mapped);
    });

    my $thread_len = $thr->join();
    is($thread_len, length($content), "thread sees correct length of mmap'd variable");
    is($mapped, $content, "main thread mapping intact after thread exit");

    munmap($mapped);
}

# Test 3-5: thread clone of writable mmap'd variable
{
    my $mapped;
    sysopen(my $fh, $temp_file, O_RDWR) or die "$temp_file: $!\n";
    mmap($mapped, 0, PROT_READ|PROT_WRITE, MAP_SHARED, $fh);
    close $fh;

    my $thr = threads->create(sub {
        return substr($mapped, 0, 16);
    });

    my $thread_data = $thr->join();
    is($thread_data, substr($content, 0, 16), "thread reads correct data from mmap'd variable");
    is(length($mapped), length($content), "main thread length unchanged after thread exit");

    substr($mapped, 0, 4) = "PASS";
    is(substr($mapped, 0, 4), "PASS", "main thread can still write after thread exit");

    munmap($mapped);
}

# Test 6-7: anonymous mmap survives thread clone
{
    my $mapped;
    mmap($mapped, 4096, PROT_READ|PROT_WRITE, MAP_SHARED|MAP_ANON, *STDOUT);

    substr($mapped, 0, 5) = "Hello";

    my $thr = threads->create(sub {
        return substr($mapped, 0, 5);
    });

    my $thread_data = $thr->join();
    is($thread_data, "Hello", "thread reads anonymous mmap data");
    is(substr($mapped, 0, 5), "Hello", "main thread anonymous mmap intact after thread exit");

    munmap($mapped);
}

unlink($temp_file);
