#!perl -w

use strict;
use Benchmark::Forking qw(cmpthese);

use Config; printf "Perl/%vd on %s\n", $^V, $Config{archname};

cmpthese -3, {
    'plain' => sub{
        require optimizer::hotspot;
        optimizer::hotspot->unimport;

        require Math::BigInt;

        my $i = Math::BigInt->new(100);
        $i++ for(1 .. 100);
    },
    'optimized' => sub{
        require optimizer::hotspot;
        optimizer::hotspot->import;

        require Math::BigInt;

        my $i = Math::BigInt->new(100);
        $i++ for(1 .. 100);
    }
};

