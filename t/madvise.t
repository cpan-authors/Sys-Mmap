#! perl

use strict;
use warnings;

use Test::More;
use Sys::Mmap;
use Fcntl qw(O_RDONLY O_WRONLY O_CREAT O_TRUNC);

my $temp_file = "madvise.tmp";

# ---- Constants ----

my @posix_constants = qw(MADV_NORMAL MADV_RANDOM MADV_SEQUENTIAL MADV_WILLNEED MADV_DONTNEED);

my $plan = 0;

# Test POSIX constants (should be available everywhere mmap is)
for my $name (@posix_constants) {
    $plan += 2;
}

# madvise on read-write mapping: 3 tests per advice value + 1 munmap
$plan += scalar(@posix_constants) * 3 + 1;

# madvise on read-only mapping: 2
$plan += 2;

# madvise with offset: 2
$plan += 2;

# error cases: 4
$plan += 4;

# MADV_FREE (optional): tested only if available
my $have_madv_free = eval { MADV_FREE(); 1 };
$plan += 2 if $have_madv_free;

plan tests => $plan;

# ---- POSIX constants ----

for my $name (@posix_constants) {
    no strict 'refs';
    my $val = eval { &{"Sys::Mmap::$name"}() };
    ok(defined $val, "$name is defined");
    like($val, qr/^\d+$/, "$name is an integer ($val)");
}

# ---- madvise on read-write file mapping ----

{
    # Create a test file
    sysopen(my $fh_w, $temp_file, O_WRONLY|O_CREAT|O_TRUNC) or die "$temp_file: $!\n";
    print $fh_w "X" x 8192;
    close $fh_w;

    sysopen(my $fh, $temp_file, O_RDONLY) or die "$temp_file: $!\n";
    my $data;
    mmap($data, 0, PROT_READ, MAP_SHARED, $fh);
    close $fh;

    for my $name (@posix_constants) {
        no strict 'refs';
        my $val = &{"Sys::Mmap::$name"}();
        my $ret = eval { madvise($data, $val) };
        ok(defined $ret, "madvise with $name succeeds");
        is($ret, 1, "madvise with $name returns 1");
        is(length($data), 8192, "data intact after madvise with $name");
    }

    munmap($data);
    pass("munmap after madvise succeeds");
}

# ---- madvise on read-only mapping ----

{
    sysopen(my $fh, $temp_file, O_RDONLY) or die "$temp_file: $!\n";
    my $data;
    mmap($data, 0, PROT_READ, MAP_SHARED, $fh);
    close $fh;

    my $ret = eval { madvise($data, MADV_SEQUENTIAL()) };
    ok(defined $ret, "madvise MADV_SEQUENTIAL on read-only mapping succeeds");
    is($ret, 1, "madvise returns 1 on read-only mapping");

    munmap($data);
}

# ---- madvise with non-zero offset ----

{
    sysopen(my $fh, $temp_file, O_RDONLY) or die "$temp_file: $!\n";
    my $data;
    mmap($data, 4096, PROT_READ, MAP_SHARED, $fh, 100);
    close $fh;

    my $ret = eval { madvise($data, MADV_RANDOM()) };
    ok(defined $ret, "madvise on offset mapping succeeds");
    is($ret, 1, "madvise returns 1 on offset mapping");

    munmap($data);
}

# ---- Error cases ----

# madvise on undef
{
    my $var;
    eval { madvise($var) };
    like($@, qr/not defined/, "madvise on undef variable croaks");
}

# madvise on plain integer
{
    my $var = 42;
    eval { madvise($var) };
    like($@, qr/not a string/, "madvise on integer croaks");
}

# madvise on regular (non-mmap'd) string
{
    my $var = "hello world";
    eval { madvise($var) };
    like($@, qr/does not appear to be mmap/, "madvise on regular string croaks");
}

# madvise default advice (no second arg)
{
    sysopen(my $fh, $temp_file, O_RDONLY) or die "$temp_file: $!\n";
    my $data;
    mmap($data, 0, PROT_READ, MAP_SHARED, $fh);
    close $fh;

    my $ret = eval { madvise($data) };
    ok(defined $ret, "madvise with default advice (MADV_NORMAL) succeeds");

    munmap($data);
}

# ---- MADV_FREE (optional, Linux 4.5+ / FreeBSD) ----
# MADV_FREE only works on private anonymous pages

if ($have_madv_free) {
    my $data;
    mmap($data, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANON(), *STDOUT);

    my $ret = eval { madvise($data, MADV_FREE()) };
    ok(defined $ret, "madvise with MADV_FREE on private anon mapping succeeds");
    is($ret, 1, "madvise MADV_FREE returns 1");

    munmap($data);
}

# ---- Cleanup ----

unlink $temp_file;
