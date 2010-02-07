#!perl -w

use strict;
use Benchmark::Forking qw(cmpthese);

use FindBin qw($Bin);

use Config; printf "Perl/%vd on %s\n", $^V, $Config{archname};

print "This is arbitrary test :)\n";

cmpthese -3, {
    'plain' => sub{
        require optimizer::hotspot;
        optimizer::hotspot->unimport;

        my $f = eval q{
            sub {
                my($a, $b, $c, $d) = @_;
                ($a, $b, $c, $d) = @_;
                ($a, $b, $c, $d) = @_;

                return $a + $b + $c + $d;
            }
        };

        $f->(1, 2, 3, 4) for(1 .. 1000);
    },
    'optimized' => sub{
        require optimizer::hotspot;
        optimizer::hotspot->import;

        my $f = eval q{
            sub {
                my($a, $b, $c, $d) = @_;
                ($a, $b, $c, $d) = @_;
                ($a, $b, $c, $d) = @_;

                return $a + $b + $c + $d;
            }
        };

        $f->(1, 2, 3, 4) for(1 .. 1000);
    }
};

