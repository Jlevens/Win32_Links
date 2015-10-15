
use File::FindLib 'lib';
use Setup;

my %h = ( a => 1, b => 2, c => 'D' );
use Win32::Links opt_in => \%h => opt_out => 'STD' => C => Banana => 'apple';

symlink( "lib", "W32_lib_s" );

link( "README.md", "W32_rm_l" );
link( "lib", "W32_lib_l" );
symlink( "README.md", "W32_rm_s" );
symlink( "Empty.txt", "W32_empty_s" );

say "\n";
for my $f (qw( W32_lib_s W32_rm_l W32_rm_s Empty.txt W32_empty_s )) {
    say "";
    say "$f " . ( -f $f ? 'is' : 'not') . " a file";
    say "$f " . ( -e $f ? 'is' : 'not') . " existing";
    say "$f " . ( -l $f ? 'is' : 'not') . " a symlink";
    say "$f " . ( is_l($f) ? 'is' : 'not') . " a symlink";
    say "$f " . ( -d $f ? 'is' : 'not') . " a directory";
    say "$f " . ( -z $f ? 'is' : 'not') . " empty";
}


exit 0;