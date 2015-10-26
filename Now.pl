
use File::FindLib 'lib';
use Setup;

use Win32::Symlink;
use Win32::Hardlink;

symlink( "lib", "W32X_lib_s" );
symlink( "README.md", "W32X_rm_s" );

link( "README.md", "W32X_rm_h" );

