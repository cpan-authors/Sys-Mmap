#! perl

use strict;
use warnings;

use Test::More tests => 7;

use Sys::Mmap;
use Fcntl qw(O_WRONLY O_CREAT O_TRUNC O_RDONLY O_RDWR);

my $temp_file = "hardwire.tmp";
my $content = "A" x 4096 . "B" x 4096;

sysopen(my $fh_w, $temp_file, O_WRONLY|O_CREAT|O_TRUNC) or die "$temp_file: $!\n";
print $fh_w $content;
close $fh_w;

# mmap a file, capture the returned address, hardwire a second variable to it
{
    my $mapped;
    sysopen(my $fh, $temp_file, O_RDONLY) or die "$temp_file: $!\n";
    my $addr = mmap($mapped, 0, PROT_READ, MAP_SHARED, $fh);
    close $fh;

    ok(defined $addr, "mmap returns a defined address");
    # Address should be an integer, not a float
    like("$addr", qr/^\d+\z/, "mmap address is an integer (no decimal point)");

    my $wired;
    Sys::Mmap::hardwire($wired, $addr, 4096);
    is(length($wired), 4096, "hardwire: variable has correct length");
    is($wired, "A" x 4096, "hardwire: variable sees mmap'd content");

    # hardwire at an offset within the mapped region
    my $wired2;
    Sys::Mmap::hardwire($wired2, $addr + 4096, 4096);
    is(length($wired2), 4096, "hardwire: offset variable has correct length");
    is($wired2, "B" x 4096, "hardwire: offset variable sees correct content");

    # Clean up the primary mapping (hardwire'd vars become invalid after this)
    munmap($mapped);
    pass("hardwire: survived munmap of underlying region");
}

unlink($temp_file);
