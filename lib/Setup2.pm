package Setup2;
BEGIN {
    require Exporter;
    our $VERSION     = 0.001;
    our @ISA         = qw(Exporter);
    our @EXPORT      = qw($scriptDir);
    }

use Cwd qw(abs_path);
use File::Basename;
our $scriptDir = dirname abs_path(__FILE__ . '/..');

1;
