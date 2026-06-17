#! perl

use strict;
use warnings;

use Test::More;
use Sys::Mmap;
use Fcntl qw(O_WRONLY O_CREAT O_TRUNC O_RDONLY O_RDWR);

my $temp_file = "destroy.tmp";
my $pagesize  = 4096;

sub create_test_file {
    my ($size) = @_;
    sysopen(my $fh, $temp_file, O_WRONLY|O_CREAT|O_TRUNC) or die "$temp_file: $!\n";
    print $fh ("\0" x $size);
    close $fh;
}

# Raw mmap: scope exit after explicit munmap must not double-munmap
{
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, $_[0] };
    {
        my $data;
        mmap($data, $pagesize, PROT_READ|PROT_WRITE, MAP_SHARED|MAP_ANON, *STDOUT);
        ok(defined $data, "anon mmap succeeded");
        munmap($data);
        ok(!defined $data, "explicit munmap cleared variable");
    }
    pass("scope exit after explicit munmap: no crash");
    is(scalar(grep { /munmap/ } @warnings), 0,
       "no munmap warnings on scope exit after explicit munmap");
}

# Raw mmap with file: scope exit after explicit munmap
{
    create_test_file($pagesize);
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, $_[0] };
    {
        my $data;
        sysopen(my $fh, $temp_file, O_RDWR) or die "$temp_file: $!\n";
        mmap($data, $pagesize, PROT_READ|PROT_WRITE, MAP_SHARED, $fh);
        close $fh;
        ok(defined $data, "file mmap succeeded");
        munmap($data);
    }
    pass("file mmap: scope exit after explicit munmap");
    is(scalar(grep { /munmap/ } @warnings), 0,
       "file mmap: no munmap warnings on scope exit");
}

# Raw mmap: implicit cleanup via scope exit (no explicit munmap)
{
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, $_[0] };
    {
        my $data;
        mmap($data, $pagesize, PROT_READ|PROT_WRITE, MAP_SHARED|MAP_ANON, *STDOUT);
        substr($data, 0, 5) = "hello";
        is(substr($data, 0, 5), "hello", "mmap'd data writable before scope exit");
    }
    pass("implicit cleanup via scope exit: no crash");
    is(scalar(grep { /munmap/ } @warnings), 0,
       "implicit cleanup: no munmap warnings");
}

# Tied interface: DESTROY must not throw (uses warn, not croak)
{
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, $_[0] };
    my $exception = '';
    eval {
        my $var;
        Sys::Mmap->new($var, $pagesize);
        $var = "test";
        is(substr($var, 0, 4), "test", "tied var writable before DESTROY");
    };
    $exception = $@ if $@;
    is($exception, '', "tied DESTROY: no exception thrown");
    is(scalar(grep { /munmap/ } @warnings), 0,
       "tied DESTROY: no munmap warnings");
}

# Tied interface with file: DESTROY cleanup
{
    create_test_file($pagesize);
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, $_[0] };
    eval {
        my $var;
        Sys::Mmap->new($var, $pagesize, $temp_file);
        $var = "file data";
        is(substr($var, 0, 9), "file data", "tied file var writable before DESTROY");
    };
    is($@, '', "tied file DESTROY: no exception thrown");
    is(scalar(grep { /munmap/ } @warnings), 0,
       "tied file DESTROY: no munmap warnings");
}

unlink($temp_file);
done_testing();
