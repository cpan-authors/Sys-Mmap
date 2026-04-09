#! perl

use strict;
use warnings;

use Test::More;
use Sys::Mmap;
use Fcntl qw(O_RDONLY);

my $temp_file = "tied.tmp";

# ---- new() argument validation ----

{
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, $_[0] };

    my $ret = Sys::Mmap->new(my $var);
    is($ret, undef, "new() with too few args returns undef");
    ok(grep { /Usage:/ } @warnings, "new() with too few args warns about usage");
    ok(!tied($var), "variable is not tied after failed new()");
}

{
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, $_[0] };

    my $ret = Sys::Mmap->new(my $var, 4096, "/nonexistent/path/$$");
    is($ret, undef, "new() with nonexistent file returns undef");
    ok(grep { /could not open/ } @warnings, "new() with bad file warns about open failure");
}

# ---- STORE truncation: value longer than mapping ----

{
    # Create a small mapping
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, $_[0] };

    my $var;
    my $maplen = 64;
    my $obj = Sys::Mmap->new($var, $maplen);
    ok(defined $obj, "new() with anonymous memory succeeds");
    ok(tied($var), "variable is tied");
    is(length($var), $maplen, "mapping has requested length");

    # Assign a value longer than the mapping
    my $long_value = "X" x 200;
    $var = $long_value;
    is(length($var), $maplen, "STORE: mapping length preserved after oversized assignment");
    is($var, "X" x $maplen, "STORE: value truncated to mapping length");

    # Assign exactly the mapping length
    my $exact_value = "Y" x $maplen;
    $var = $exact_value;
    is($var, $exact_value, "STORE: exact-length assignment works");

    # Assign shorter than the mapping
    my $short_value = "Z" x 10;
    $var = $short_value;
    is(substr($var, 0, 10), $short_value, "STORE: short assignment writes at beginning");
    # Remainder should be from previous write
    is(substr($var, 10, 1), "Y", "STORE: short assignment preserves rest of mapping");

    my @munmap_warns = grep { /munmap failed/ } @warnings;
    is(scalar @munmap_warns, 0, "no munmap failures during test");
}

# ---- FETCH returns full mapping ----

{
    # Create a file with known content
    my $content = "Hello, mmap tied!" . ("\0" x (4096 - 17));
    sysopen(my $fh_w, $temp_file, Fcntl::O_WRONLY|Fcntl::O_CREAT|Fcntl::O_TRUNC) or die "$temp_file: $!\n";
    print $fh_w $content;
    close $fh_w;

    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, $_[0] };

    {
        my $var;
        Sys::Mmap->new($var, 4096, $temp_file);
        ok(tied($var), "tied file: variable is tied");

        my $fetched = $var;  # exercises FETCH
        is(length($fetched), 4096, "FETCH: returns full mapping length");
        is(substr($fetched, 0, 17), "Hello, mmap tied!", "FETCH: returns correct content");
    }

    my @munmap_warns = grep { /munmap failed/ } @warnings;
    is(scalar @munmap_warns, 0, "no munmap failures during tied file test");
}

# ---- len=0 with tied interface (infer from file size) ----

{
    # Create a 2048-byte file
    sysopen(my $fh_w, $temp_file, Fcntl::O_WRONLY|Fcntl::O_CREAT|Fcntl::O_TRUNC) or die "$temp_file: $!\n";
    print $fh_w "Q" x 2048;
    close $fh_w;

    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, $_[0] };

    {
        my $var;
        Sys::Mmap->new($var, 0, $temp_file);
        ok(tied($var), "len=0 tied: variable is tied");
        is(length($var), 2048, "len=0 tied: infers length from file size");
        is($var, "Q" x 2048, "len=0 tied: content matches file");
    }

    my @munmap_warns = grep { /munmap failed/ } @warnings;
    is(scalar @munmap_warns, 0, "no munmap failures during len=0 tied test");
}

# ---- Multiple STORE calls ----

{
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, $_[0] };

    my $var;
    Sys::Mmap->new($var, 128);
    ok(tied($var), "multi-store: variable is tied");

    $var = "AAAA";
    is(substr($var, 0, 4), "AAAA", "multi-store: first write");

    $var = "BB";
    is(substr($var, 0, 2), "BB", "multi-store: second write overwrites beginning");
    # Bytes 2-3 should still have data from first write
    is(substr($var, 2, 2), "AA", "multi-store: second write preserves rest");

    my @munmap_warns = grep { /munmap failed/ } @warnings;
    is(scalar @munmap_warns, 0, "no munmap failures during multi-store test");
}

# ---- Tied variable with substr() lvalue ----

{
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, $_[0] };

    my $var;
    Sys::Mmap->new($var, 256);
    ok(tied($var), "substr: variable is tied");

    # Write at specific offset via substr
    $var = "A" x 256;
    substr($var, 100, 5) = "HELLO";
    is(substr($var, 100, 5), "HELLO", "substr: write at offset works");
    is(substr($var, 0, 3), "AAA", "substr: data before offset preserved");
    is(substr($var, 105, 3), "AAA", "substr: data after write preserved");

    my @munmap_warns = grep { /munmap failed/ } @warnings;
    is(scalar @munmap_warns, 0, "no munmap failures during substr test");
}

# Cleanup
unlink($temp_file);

done_testing;
