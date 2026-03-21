#! perl

use strict;
use warnings;

use Test::More;
use Sys::Mmap;
use Fcntl qw(O_WRONLY O_CREAT O_TRUNC O_RDONLY O_RDWR);

my $temp_file = "comprehensive.tmp";
my $file_size = 8192;

# Create a test file with known content
sub create_test_file {
    my ($size, $pattern) = @_;
    $pattern //= "ABCD1234";
    sysopen(my $fh, $temp_file, O_WRONLY|O_CREAT|O_TRUNC) or die "$temp_file: $!\n";
    my $content = ($pattern x int($size / length($pattern) + 1));
    $content = substr($content, 0, $size);
    print $fh $content;
    close $fh;
    return $content;
}

# ---- Tied interface tests (new / TIESCALAR) ----

subtest 'tied interface with file' => sub {
    my $content = create_test_file(4096);

    # The tied interface's DESTROY has a pre-existing issue: it receives
    # the blessed reference SV, not the mmap'd SV, so munmap fails with
    # EINVAL during cleanup. Suppress the resulting warnings.
    local $SIG{__WARN__} = sub {
        warn $_[0] unless $_[0] =~ /munmap failed|untie attempted/;
    };

    {
        my $var;
        my $obj = Sys::Mmap->new($var, 4096, $temp_file);
        ok(defined $obj, "new() returns a defined object");
        ok(tied($var), "variable is tied after new()");
        is(length($var), 4096, "tied variable has correct length");
        is($var, $content, "tied variable has correct content");

        # Test STORE: writing through tied interface
        my $new_data = "HELLO";
        $var = $new_data;
        is(substr($var, 0, length($new_data)), $new_data, "STORE writes data at beginning");
        # Rest of mapping should be unchanged
        is(substr($var, length($new_data), 4), substr($content, length($new_data), 4), "STORE preserves rest of data");
        # Let $var and $obj go out of scope together to avoid untie warnings
    }
    pass("tied file variable cleaned up without crash");
};

subtest 'tied interface with anonymous memory' => sub {
    local $SIG{__WARN__} = sub {
        warn $_[0] unless $_[0] =~ /munmap failed|untie attempted/;
    };

    {
        my $var;
        my $obj = Sys::Mmap->new($var, 4096);
        ok(defined $obj, "new() with anonymous memory returns defined object");
        ok(tied($var), "variable is tied for anonymous memory");
        is(length($var), 4096, "anonymous tied variable has correct length");

        $var = "test data";
        is(substr($var, 0, 9), "test data", "STORE works on anonymous memory");
    }
    pass("tied anonymous memory cleaned up without crash");
};

subtest 'tied interface grows small files' => sub {
    local $SIG{__WARN__} = sub {
        warn $_[0] unless $_[0] =~ /munmap failed|untie attempted/;
    };

    # Create a tiny file
    create_test_file(100);
    is(-s $temp_file, 100, "initial file is 100 bytes");

    {
        my $var;
        Sys::Mmap->new($var, 4096, $temp_file);
        ok(tied($var), "tied to grown file");
        is(length($var), 4096, "tied variable reflects grown size");
    }

    # File should have been grown to 4096
    ok(-s $temp_file >= 4096, "file was grown to requested length");
};

# ---- MAP_ANON tests ----

subtest 'MAP_ANON basic' => sub {
    my $data;
    my $addr = mmap($data, 4096, PROT_READ|PROT_WRITE, MAP_SHARED|MAP_ANON, *STDOUT);
    ok(defined $addr, "mmap with MAP_ANON succeeds");
    is(length($data), 4096, "MAP_ANON mapping has correct length");

    # Anonymous memory should be zero-filled
    is($data, "\0" x 4096, "MAP_ANON memory is zero-filled");

    # Write and read back
    substr($data, 0, 5) = "Hello";
    is(substr($data, 0, 5), "Hello", "can write to MAP_ANON region");

    munmap($data);
};

subtest 'MAP_ANON requires length' => sub {
    my $data;
    eval { mmap($data, 0, PROT_READ|PROT_WRITE, MAP_SHARED|MAP_ANON, *STDOUT) };
    like($@, qr/MAP_ANON.*no length/i, "MAP_ANON with len=0 croaks");
};

# ---- len=0 with offset: inferred length should be file_size - offset ----

subtest 'len=0 infers full file size' => sub {
    my $content = create_test_file(8192);

    my $data;
    sysopen(my $fh, $temp_file, O_RDONLY) or die "$temp_file: $!\n";
    mmap($data, 0, PROT_READ, MAP_SHARED, $fh);
    close $fh;

    is(length($data), 8192, "len=0 infers full file size");
    is($data, $content, "len=0 maps entire file content");
    munmap($data);
};

subtest 'len=0 with offset infers remaining size' => sub {
    my $content = create_test_file(8192);
    my $offset = 4096;

    my $data;
    sysopen(my $fh, $temp_file, O_RDONLY) or die "$temp_file: $!\n";
    mmap($data, 0, PROT_READ, MAP_SHARED, $fh, $offset);
    close $fh;

    is(length($data), 8192 - $offset, "len=0 with offset infers file_size - offset");
    is($data, substr($content, $offset), "content matches file from offset");
    munmap($data);
};

subtest 'len=0 with non-page-aligned offset' => sub {
    my $content = create_test_file(8192);
    my $offset = 256;  # likely not page-aligned

    my $data;
    sysopen(my $fh, $temp_file, O_RDONLY) or die "$temp_file: $!\n";
    mmap($data, 0, PROT_READ, MAP_SHARED, $fh, $offset);
    close $fh;

    is(length($data), 8192 - $offset, "len=0 with non-aligned offset infers correct remaining size");
    is($data, substr($content, $offset), "content matches from non-aligned offset");
    munmap($data);
};

subtest 'len=0 with offset at EOF croaks' => sub {
    create_test_file(4096);

    my $data;
    sysopen(my $fh, $temp_file, O_RDONLY) or die "$temp_file: $!\n";
    eval { mmap($data, 0, PROT_READ, MAP_SHARED, $fh, 4096) };
    close $fh;
    like($@, qr/offset.*beyond end of file/i, "offset at EOF croaks");
};

subtest 'len=0 with offset beyond EOF croaks' => sub {
    create_test_file(4096);

    my $data;
    sysopen(my $fh, $temp_file, O_RDONLY) or die "$temp_file: $!\n";
    eval { mmap($data, 0, PROT_READ, MAP_SHARED, $fh, 8192) };
    close $fh;
    like($@, qr/offset.*beyond end of file/i, "offset beyond EOF croaks");
};

# ---- Explicit offset with explicit length ----

subtest 'explicit offset with explicit length' => sub {
    my $content = create_test_file(8192);
    my $offset = 4096;
    my $len = 1024;

    my $data;
    sysopen(my $fh, $temp_file, O_RDONLY) or die "$temp_file: $!\n";
    mmap($data, $len, PROT_READ, MAP_SHARED, $fh, $offset);
    close $fh;

    is(length($data), $len, "explicit offset+length: correct length");
    is($data, substr($content, $offset, $len), "explicit offset+length: correct content");
    munmap($data);
};

# ---- DESTROY cleanup (implicit munmap via scope exit) ----

subtest 'DESTROY cleanup without explicit munmap' => sub {
    my $content = create_test_file(8192);

    {
        my $data;
        sysopen(my $fh, $temp_file, O_RDONLY) or die "$temp_file: $!\n";
        mmap($data, 0, PROT_READ, MAP_SHARED, $fh);
        close $fh;
        is(length($data), 8192, "mmap succeeded before scope exit");
        # $data goes out of scope - DESTROY called implicitly
    }
    pass("survived DESTROY without explicit munmap");
};

# Cleanup
unlink($temp_file);

done_testing;
