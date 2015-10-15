
use File::FindLib 'lib';
use Setup;

my %h = ( a => 1, b => 2, c => 'D' );
use Win32::Links opt_in => \%h => opt_out => 'STD' => C => Banana => 'apple';

symlink( "lib", "W32_lib_s" );

link( "README.md", "W32_rm_l" );
link( "lib", "W32_lib_l" );
symlink( "README.md", "W32_rm_s" );

say (readlink( $_ ) // '**') for (qw( W32_lib_s W32_rm_l W32_rm_s ));
for my $f (qw( W32_lib_s W32_rm_l W32_rm_s )) {
    say "$f " . (is_l($f) ? 'is' : 'not') . " a symlink";
}

exit 0;