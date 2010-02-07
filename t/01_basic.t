#!perl -w

use strict;

use Test::More;

use optimizer::hotspot;

use Math::Complex;

for(1 .. 100){
    is(Math::Complex->new(42),     42);
    is(Math::Complex->new(42) + 1, 43);
    is(Math::Complex->new(42) - 1, 41);
}


done_testing;
