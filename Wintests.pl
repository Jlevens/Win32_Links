
use File::FindLib 'lib';
use Setup;

use Win32::Links opt_in => { a => 1, b => 2, c => 'D' } => opt_out => 'STD' => C => Banana => 'apple';

symlink( "lib", "W32_lib_s" );

link( "README.md", "W32_rm_l" );
link( "lib", "W32_lib_l" );
symlink( "README.md", "W32_rm_s" );
symlink( "Empty.txt", "W32_empty_s" );

for my $f (qw( W32_lib_s W32_rm_l W32_rm_s Empty.txt W32_empty_s )) {
    say "";
    say "$f " . ( -f $f ? 'is' : 'not') . " a file";
    say "$f " . ( -e $f ? 'is' : 'not') . " existing";
    say "$f " . ( -l $f ? 'is' : 'not') . " a symlink";
    say "$f " . ( -d $f ? 'is' : 'not') . " a directory";
    say "$f " . ( -z $f ? 'is' : 'not') . " empty";
}
say "\n";

use Win32API::File qw(:ALL);

my @stat1 = stat( "W32_rm_s" );
my @stat2 = stat( "README.md" );
my @stat3 = lstat( "W32_rm_s" );
my @stat4 = lstat( "README.md" );
#
local $, = " -- ";
say @stat1;
say "";
say @stat2;
say "";
say @stat3;
say "";
say @stat4;
say "";

exit 0;