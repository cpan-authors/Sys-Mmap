#! perl

use strict;
use warnings;

use Test::More tests => 11;

use Sys::Mmap;
use Fcntl qw(O_WRONLY O_CREAT O_TRUNC O_RDONLY O_RDWR);

my $temp_file = "mprotect.tmp";
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

# ---- mprotect: downgrade writable mapping to read-only ----

{
    create_test_file($file_size);

    my $data;
    sysopen(my $fh, $temp_file, O_RDWR) or die "$temp_file: $!\n";
    mmap($data, 0, PROT_READ|PROT_WRITE, MAP_SHARED, $fh);
    close $fh;

    # Should be writable initially
    ok(!Internals::SvREADONLY($data), "mprotect: variable is writable after RW mmap");

    substr($data, 0, 5) = "Hello";
    is(substr($data, 0, 5), "Hello", "mprotect: can write before mprotect");

    # Downgrade to read-only
    my $ret = mprotect($data, PROT_READ);
    is($ret, 1, "mprotect: returns 1 on success");

    # Perl's SvREADONLY should now be set
    ok(Internals::SvREADONLY($data), "mprotect: variable is read-only after PROT_READ");

    munmap($data);
}

# ---- mprotect: upgrade read-only mapping to writable ----

{
    create_test_file($file_size);

    my $data;
    sysopen(my $fh, $temp_file, O_RDWR) or die "$temp_file: $!\n";
    # Map read-only first (note: fd must be opened O_RDWR for later mprotect to succeed)
    mmap($data, 0, PROT_READ, MAP_SHARED, $fh);
    close $fh;

    ok(Internals::SvREADONLY($data), "mprotect: variable is read-only after RO mmap");

    # Upgrade to read-write
    my $ret = mprotect($data, PROT_READ|PROT_WRITE);
    is($ret, 1, "mprotect: upgrade to PROT_READ|PROT_WRITE returns 1");
    ok(!Internals::SvREADONLY($data), "mprotect: variable is writable after upgrade");

    # Should be able to write now
    substr($data, 0, 4) = "TEST";
    is(substr($data, 0, 4), "TEST", "mprotect: can write after upgrading to PROT_WRITE");

    munmap($data);
}

# ---- mprotect error cases ----

{
    my $undef_var;
    eval { mprotect($undef_var, PROT_READ) };
    like($@, qr/mprotect: variable is not defined/, "mprotect: undef variable croaks");
}

{
    my $str = "not mmap'd";
    eval { mprotect($str, PROT_READ) };
    like($@, qr/mprotect:/, "mprotect: plain string croaks");
}

# ---- mprotect with non-zero offset mapping ----

{
    create_test_file($file_size);

    my $data;
    sysopen(my $fh, $temp_file, O_RDWR) or die "$temp_file: $!\n";
    mmap($data, 4096, PROT_READ|PROT_WRITE, MAP_SHARED, $fh, 256);
    close $fh;

    my $ret = mprotect($data, PROT_READ);
    is($ret, 1, "mprotect: works with non-zero offset mapping");

    munmap($data);
}

# Cleanup
unlink($temp_file);
