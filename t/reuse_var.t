#! perl

# Test that mmap() and hardwire() properly free existing string buffers
# when called on variables that already hold values (prevents memory leak).

use strict;
use warnings;

use Test::More tests => 8;
use Sys::Mmap;
use Fcntl qw(O_WRONLY O_CREAT O_TRUNC O_RDONLY O_RDWR);

my $temp_file = "reuse_var.tmp";
my $content   = "REUSE_TEST" x 500;    # 5000 bytes

# Create test file
sysopen( my $wfh, $temp_file, O_WRONLY | O_CREAT | O_TRUNC ) or die "$temp_file: $!\n";
print $wfh $content;
close $wfh;

# ---- mmap into a variable that already holds a string ----

{
    my $var = "x" x 1024;    # pre-existing allocated string
    is( length($var), 1024, "mmap reuse: var starts with existing string" );

    sysopen( my $fh, $temp_file, O_RDONLY ) or die "$temp_file: $!\n";
    mmap( $var, 0, PROT_READ, MAP_SHARED, $fh );
    close $fh;

    is( length($var), length($content), "mmap reuse: length matches file after mmap" );
    is( $var, $content, "mmap reuse: content matches file after mmap" );
    munmap($var);
}

# ---- mmap read-write into a pre-existing variable ----

{
    my $var = "some existing data that should be freed";

    sysopen( my $fh, $temp_file, O_RDWR ) or die "$temp_file: $!\n";
    mmap( $var, 0, PROT_READ | PROT_WRITE, MAP_SHARED, $fh );
    close $fh;

    is( $var, $content, "mmap rw reuse: content is correct" );

    # Write through the mapping
    substr( $var, 0, 10 ) = "XXXXXXXXXX";
    is( substr( $var, 0, 10 ), "XXXXXXXXXX", "mmap rw reuse: write works" );
    munmap($var);
}

# ---- hardwire into a variable that already holds a string ----

# Re-create test file (previous test modified it)
sysopen( $wfh, $temp_file, O_WRONLY | O_CREAT | O_TRUNC ) or die "$temp_file: $!\n";
print $wfh $content;
close $wfh;

{
    # mmap_var must outlive the hardwired var to avoid SEGV on cleanup
    # (hardwire doesn't track the underlying mapping - documented limitation)
    my $mmap_var;
    sysopen( my $fh, $temp_file, O_RDONLY ) or die "$temp_file: $!\n";
    my $addr = mmap( $mmap_var, 0, PROT_READ, MAP_SHARED, $fh );
    close $fh;

    ok( defined $addr, "hardwire reuse: got mmap address" );

    {
        my $var = "pre-existing string for hardwire";

        # hardwire into the variable that already has a string
        Sys::Mmap::hardwire( $var, $addr, length($content) );
        is( length($var), length($content), "hardwire reuse: length correct" );
        is( substr( $var, 0, 10 ), "REUSE_TEST", "hardwire reuse: content accessible" );

        # $var goes out of scope here while mmap_var is still alive
    }

    munmap($mmap_var);
}

# Cleanup
unlink($temp_file);
