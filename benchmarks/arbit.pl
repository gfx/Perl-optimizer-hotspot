#!perl -w

use strict;
use Benchmark::Forking qw(cmpthese);

use Config; printf "Perl/%vd on %s\n", $^V, $Config{archname};

use FindBin qw($Bin);

cmpthese -3, {
    'plain' => sub{
        require optimizer::hotspot;
        optimizer::hotspot->unimport;

        my $f = eval q{
            sub {
                my($a, $b, $c) = @_;
                return $a + $b + $c;
            }
        };

        $f->(1, 2, 3) for(1 .. 1000);
    },
    'optimized' => sub{
        require optimizer::hotspot;
        optimizer::hotspot->import;

        my $f = eval q{
            sub {
                my($a, $b, $c) = @_;
                return $a + $b + $c;
            }
        };

        $f->(1, 2, 3) for(1 .. 1000);
    }
};

