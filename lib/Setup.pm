package Setup;
use parent 'Import::Base';

our @IMPORT_MODULES = (
    'strict',
    'warnings',
    'feature' => [ qw( :5.14 ) ], # I like to 'say' things
    'Setup2',
);

1;