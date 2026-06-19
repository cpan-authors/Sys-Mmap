#! perl

use strict;
use warnings;

use Test::More tests => 8;
use Sys::Mmap;
use Fcntl qw(O_RDONLY O_WRONLY O_CREAT O_TRUNC);

my $temp_file = "closed_fh.tmp";

# Create a test file
sysopen(my $fh_w, $temp_file, O_WRONLY|O_CREAT|O_TRUNC) or die "$temp_file: $!\n";
print $fh_w "A" x 4096;
close $fh_w;

# ---- Closed filehandle should croak, not segfault ----

{
    sysopen(my $fh, $temp_file, O_RDONLY) or die "$temp_file: $!\n";
    close $fh;
    eval { mmap(my $data, 100, PROT_READ, MAP_SHARED, $fh) };
    like($@, qr/not open/, "closed filehandle croaks with helpful message");
}

# ---- Valid filehandle still works ----

{
    sysopen(my $fh, $temp_file, O_RDONLY) or die "$temp_file: $!\n";
    my $data;
    mmap($data, 0, PROT_READ, MAP_SHARED, $fh);
    close $fh;
    is(length($data), 4096, "valid filehandle: correct mapping length");
    is(substr($data, 0, 4), "AAAA", "valid filehandle: correct content");
    munmap($data);
}

# ---- Bareword filehandle works ----

{
    sysopen(FOO, $temp_file, O_RDONLY) or die "$temp_file: $!\n";
    my $data;
    mmap($data, 0, PROT_READ, MAP_SHARED, FOO);
    close FOO;
    is(length($data), 4096, "bareword filehandle: correct mapping length");
    munmap($data);
}

# ---- MAP_ANON ignores the filehandle argument ----

{
    my $data;
    mmap($data, 4096, PROT_READ|PROT_WRITE, MAP_SHARED|MAP_ANON, *STDOUT);
    is(length($data), 4096, "MAP_ANON with STDOUT: mapping works");
    munmap($data);
}

{
    sysopen(my $fh, $temp_file, O_RDONLY) or die "$temp_file: $!\n";
    close $fh;
    my $data;
    mmap($data, 4096, PROT_READ|PROT_WRITE, MAP_SHARED|MAP_ANON, $fh);
    is(length($data), 4096, "MAP_ANON with closed fh: mapping works (fh ignored)");
    munmap($data);
}

# ---- Glob reference works ----

{
    sysopen(my $fh, $temp_file, O_RDONLY) or die "$temp_file: $!\n";
    my $data;
    mmap($data, 0, PROT_READ, MAP_SHARED, $fh);
    close $fh;
    is(length($data), 4096, "glob reference: correct mapping length");
    munmap($data);
}

# ---- Open filehandle with len=0 infers file size ----

{
    sysopen(my $fh, $temp_file, O_RDONLY) or die "$temp_file: $!\n";
    my $data;
    mmap($data, 0, PROT_READ, MAP_SHARED, $fh);
    close $fh;
    is(length($data), 4096, "len=0: infers full file size");
    munmap($data);
}

# Cleanup
unlink($temp_file);
