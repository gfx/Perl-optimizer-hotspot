#!perl -w

use strict;
use optimizer::hotspot;

use Test::More;

use Math::BigInt;

use Data::Dumper;

for(1 .. 100){
    is(Math::BigInt->new(42),     42);
    is(Math::BigInt->new(42) + 1, 43);
    is(Math::BigInt->new(42) - 1, 41);

    like(Dumper([42]), qr/\b 42 \b/xms);
}

done_testing;
