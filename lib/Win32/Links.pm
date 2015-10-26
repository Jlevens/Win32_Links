use strict;
use warnings;
package Win32::Links;

BEGIN {
    our $VERSION    = 0.001;
    *corestat = *CORE::stat;
}
my %options;

sub import {
    use English qw( -no_match_vars ) ;

    if( $OSNAME eq 'MSWin32' ) {
        sub _install_Win32Links;
        _install_Win32Links(); # Change opcode ref '-l' filetest to call our C function

        my $pkg = shift;
        print "Importing Win32::Links $pkg\n";
        local $" = " -- ";
        print "OPTS: @_\n";

        *CORE::GLOBAL::symlink  = $pkg->can('symlink');
        *CORE::GLOBAL::link     = $pkg->can('link');
        *CORE::GLOBAL::readlink = $pkg->can('readlink');
        *CORE::GLOBAL::stat     = $pkg->can('stat');              

        options( 'STD' );
    }
}

my $code;
BEGIN {
$code = <<'END_OF_C';

#include <windows.h>

int my_CreateSymbolicLink(char* From, char* To, int isDir) {
    return CreateSymbolicLinkW( (LPCWSTR) From, (LPCWSTR) To, isDir);
}

int my_CreateHardLink(char* From, char* To) {
    return CreateHardLinkW( (LPCWSTR) From,  (LPCWSTR) To, NULL);
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
            (LPCWSTR) SvPV(svlink, PL_na),
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

static OP *
S_ft_return_false(pTHX_ SV *ret) {
    OP *next = NORMAL;
    dSP;

    if (PL_op->op_flags & OPf_REF) XPUSHs(ret);
    else			   SETs(ret);
    PUTBACK;

    if (PL_op->op_private & OPpFT_STACKING) {
        while (OP_IS_FILETEST(next->op_type)
               && next->op_private & OPpFT_STACKED)
            next = next->op_next;
    }
    return next;
}

PERL_STATIC_INLINE OP *
S_ft_return_true(pTHX_ SV *ret) {
    dSP;
    if (PL_op->op_flags & OPf_REF)
        XPUSHs(PL_op->op_private & OPpFT_STACKING ? (SV *)cGVOP_gv : (ret));
    else if (!(PL_op->op_private & OPpFT_STACKING))
        SETs(ret);
    PUTBACK;
    return NORMAL;
}

#define FT_RETURNUNDEF	return S_ft_return_false(aTHX_ &PL_sv_undef)
#define FT_RETURNNO	    return S_ft_return_false(aTHX_ &PL_sv_no)
#define FT_RETURNYES	return S_ft_return_true(aTHX_ &PL_sv_yes)

#define tryAMAGICftest_MG(chr) STMT_START { \
	if ( (SvFLAGS(*PL_stack_sp) & (SVf_ROK|SVs_GMG)) \
		&& PL_op->op_flags & OPf_KIDS) {     \
	    OP *next = S_try_amagic_ftest(aTHX_ chr);	\
	    if (next) return next;			  \
	}						   \
    } STMT_END

STATIC OP *
S_try_amagic_ftest(pTHX_ char chr) {
    SV *const arg = *PL_stack_sp;

    assert(chr != '?');
    if (!(PL_op->op_private & OPpFT_STACKING)) SvGETMAGIC(arg);

    if (SvAMAGIC(arg))
    {
	const char tmpchr = chr;
	SV * const tmpsv = amagic_call(arg,
				newSVpvn_flags(&tmpchr, 1, SVs_TEMP),
				ftest_amg, AMGf_unary);

	if (!tmpsv)
	    return NULL;

	return SvTRUE(tmpsv)
            ? S_ft_return_true(aTHX_ tmpsv) : S_ft_return_false(aTHX_ tmpsv);
    }
    return NULL;
}

PP(pp_overload_ftlink)
{
    dSP;
    I32 ok;
    SV *const svlink = *SP;

    tryAMAGICftest_MG('l');

    ENTER;
    SAVETMPS;
    
    PUSHMARK(SP);
    XPUSHs( sv_2mortal( newSVsv(svlink) ) );
    PUTBACK;

    // Calling internal sub, so its our job to definitely return 1 thing not a list, i.e. we ignore return count of result items
    call_pv ("Win32::Links::is_l", G_SCALAR);

    SPAGAIN;    // Get global SP after call_pv above
    ok = POPi;  // Get true / false of test

    FREETMPS;
    LEAVE;
//  PUTBACK; // This was the missing trick or remove with dSP(s) below

    if (ok == 1) {
//      dSP;
        if (PL_op->op_flags & OPf_REF)
            XPUSHs(PL_op->op_private & OPpFT_STACKING ? (SV *)cGVOP_gv : (&PL_sv_yes));
        else if (!(PL_op->op_private & OPpFT_STACKING))
          SETs(&PL_sv_yes);
        PUTBACK;
        return PL_op->op_next;
    }
    else {    
        OP *next = PL_op->op_next;
//      dSP;
    
        if (PL_op->op_flags & OPf_REF)
            XPUSHs(&PL_sv_no);
        else
            SETs(&PL_sv_no);
        PUTBACK;
    
        if (PL_op->op_private & OPpFT_STACKING) {
            while (OP_IS_FILETEST(next->op_type)
                   && next->op_private & OPpFT_STACKED)
                next = next->op_next;
        }
        return next;
    }
}

OP* (*real_pp_ftlink)(pTHX);

void _install_Win32Links() {
    real_pp_ftlink = PL_ppaddr[OP_FTLINK];
    PL_ppaddr[OP_FTLINK] = Perl_pp_overload_ftlink;
}

END_OF_C
}
use Inline C => $code => name => 'Win32::Links', LIBS => '-lKernel32.lib' => PREFIX => 'my_' =>
    pre_head => '#include "Links.h"';

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

# Win32 does *NOT* follow symlinks with stat
# So lstat actually works out of the box, but stat needs fixing to follow links

# Corestat uses Ansi not Wide (aka Unicode) Win API calls
# Whereas rest of this module is using Unicode calls

sub stat { 
    my ( $newfile, $opts ) = @_;
    $opts //= \%options;
    $newfile = $opts->{new_in}->( $newfile );

    my $oldfile;
    
    if( ReadLink( _to($newfile), $oldfile ) ) {
        my @f = corestat decode("UTF16-LE", $oldfile );
        return @f;
    }
    else {
        my @f = corestat $newfile;
        return @f;
    }
}

# Called from C from our '-l' filetest opcode C function
sub is_l {
    my ( $newfile, $opts ) = @_;
    $opts //= \%options;
    $newfile = $opts->{new_in}->( $newfile );

    return 1 & ReadLink( _to($newfile), my $oldfile );
}

1;
