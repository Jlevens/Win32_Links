use strict;
use warnings;
package Win32::Links;

BEGIN {
    our $VERSION    = 0.001;
}
my %options;

our $is_l = 'IS LINK';
our $banana = 'Mashed';
sub import {
    use English qw( -no_match_vars ) ;
    
    my $pkg = shift;

    print "Importing Win32::Links $pkg\n";
    local $" = " -- ";
    print "OPTS: @_\n";
    if( $OSNAME eq 'MSWin32' ) {
        *CORE::GLOBAL::symlink  = $pkg->can('symlink');
        *CORE::GLOBAL::link     = $pkg->can('link');
        *CORE::GLOBAL::readlink = $pkg->can('readlink');
        $pkg->export_to_level( 0, qw(is_l) );
#        *is_l = *is_l_win32;

        options( 'STD' );
        my $to_module = caller;
        no strict 'refs';
        *{$to_module . "::is_l"} = \&{$pkg . "::is_l"};
#        *{$to_module . "::is_l"} = *{$pkg . "::is_l"};
        return ( 'is_l' );
    }
    else {
        $pkg->export_to_level( 1, qw(is_l) );
#        *is_l = *is_l_std;
    }
}

my $code;
BEGIN {
$code = <<'END_OF_C';

#include <windows.h>

int my_CreateSymbolicLink(char* From, char* To, int isDir) {
    return CreateSymbolicLinkW(From, To, isDir);
}

int my_CreateHardLink(char* From, char* To) {
    return CreateHardLinkW(From, To, NULL);
}

//# Not found in strawberry perl Windows headers

typedef struct _REPARSE_DATA_BUFFER {
  ULONG  ReparseTag;
  USHORT ReparseDataLength;
  USHORT Reserved;
  union {
    struct {
      USHORT SubstituteNameOffset;
      USHORT SubstituteNameLength;
      USHORT PrintNameOffset;
      USHORT PrintNameLength;
      ULONG  Flags;
      WCHAR  PathBuffer[1];
    } SymbolicLinkReparseBuffer;
    struct {
      USHORT SubstituteNameOffset;
      USHORT SubstituteNameLength;
      USHORT PrintNameOffset;
      USHORT PrintNameLength;
      WCHAR  PathBuffer[1];
    } MountPointReparseBuffer;
    struct {
      UCHAR DataBuffer[4096];
    } GenericReparseBuffer;
  };
} REPARSE_DATA_BUFFER, *PREPARSE_DATA_BUFFER;

int my_ReadLink( SV* svlink, SV* target ) {
    HANDLE h;
    DWORD len;
    REPARSE_DATA_BUFFER rdb;
    BOOL ok;

    h = CreateFileW(
            SvPV(svlink, PL_na),
            FILE_READ_ATTRIBUTES,
            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
            NULL,
            OPEN_EXISTING,
            FILE_FLAG_BACKUP_SEMANTICS | FILE_ATTRIBUTE_REPARSE_POINT | FILE_FLAG_OPEN_REPARSE_POINT,
            NULL
    );
    if( h == INVALID_HANDLE_VALUE ) { //# Probably File Not Found or similar
        return 0; //# Hence it's not a Symlink
    }

    ok = DeviceIoControl (
        h,
        0x900a8, //# FSCTL_GET_REPARSE_POINT
        NULL,
        0,
        &rdb,
        0x1000, //# Max size of RDB apparently
        &len,
        NULL);

    CloseHandle( h );
    if( !ok ) {
        return 0; //# SMELL?: Quite unexpected, maybe raise exception or return error - somehow?
    }

    if( rdb.ReparseTag == IO_REPARSE_TAG_SYMLINK ) {
        char *buf = (char *) rdb.SymbolicLinkReparseBuffer.PathBuffer;
        int off = (int) rdb.SymbolicLinkReparseBuffer.PrintNameOffset;
        int len = (int) rdb.SymbolicLinkReparseBuffer.PrintNameLength;
        
        sv_setpvn( target, buf + off, len );
        return 1; //# Success
    }
    else if( rdb.ReparseTag == IO_REPARSE_TAG_MOUNT_POINT ) { //# Just for reference, but we don't care about this case
        return 0;
    }

    return 0; //# Not a reparse point at all
}
           
END_OF_C
}
use Inline C => $code => name => 'Win32::Links', LIBS => '-lKernel32.lib' => PREFIX => 'my_';

use File::Spec;

use Encode qw/encode decode/;

my $VLNP = '\\\\?\\'; # Very Long Name Prefix

sub mk_VLN {
    my ($path) = @_;
    return $path if $path =~ m/^$VLNP/;

    if( $path !~ m/^\\\\/ ) { # UNC
        return "${VLNP}UNC\\$path";
    }
    return "${VLNP}$path";
}

sub rm_VLN {
    my ($path) = @_;
    $path =~ s/^$VLNP(UNC\\)?//;
    return $path;
}

sub options {
    my ($opts) = @_;
    
    if( $opts eq 'VLN' ) { # Very Long Name: That is circa 32767 characters not merely long name 260 chars from old DOS 8.3
        %options = (
            old_in  => sub { return mk_VLN( File::Spec->canonpath( $_[0] ) ); },
            old_out => sub { return rm_VLN( $_[0] ); },
            new_in  => sub { return $_[0]; },
        );
    }
    elsif( $opts eq 'STD' ) { 
        %options = (
            old_in  => sub { return File::Spec->canonpath( $_[0] ); },
            old_out => sub { return $_[0]; },
            new_in  => sub { return $_[0]; },
        );
    }
    elsif( reftype($opts) eq 'HASH' ) {
        
    }
}               

sub _to {
    return encode("UTF16-LE", $_[0]) . "\0";
}

sub symlink {
    my ( $oldfile, $newfile, $opts ) = @_;
    $opts //= \%options;
    $oldfile = $opts->{old_in}->( $oldfile );
    $newfile = $opts->{new_in}->( $newfile );
    return 1 & CreateSymbolicLink( _to($newfile), _to($oldfile), -d $oldfile ? 1 : 0 );
}

sub link {
    my ( $oldfile, $newfile, $opts ) = @_;
    $opts //= \%options;
    $oldfile = $opts->{old_in}->( $oldfile );
    $newfile = $opts->{new_in}->( $newfile );

    return 0 if -d $oldfile; # Cannot *usually* (& usefully?) create hard links to directories: Windows & Linux
    return 1 & CreateHardLink( _to($newfile), _to($oldfile) );
}

sub readlink {
    my ( $newfile, $opts ) = @_;
    $opts //= \%options;
    $newfile = $opts->{new_in}->( $newfile );

    my $oldfile;
    ReadLink( _to($newfile), $oldfile );
    return $opts->{old_out}->( decode("UTF16-LE", $oldfile ) );
}

sub is_l {
    my ( $newfile, $opts ) = @_;
    $opts //= \%options;
    $newfile = $opts->{new_in}->( $newfile );

    return 1 & ReadLink( _to($newfile), my $oldfile );
}

sub is_l_std { return -l $_[0]; }

1;
