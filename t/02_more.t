#!perl -w

use strict;
use optimizer::hotspot;

use Test::More;

use Math::BigInt     ();
use Data::Dumper   qw(Dumper);
use File::Basename qw(basename);

for(1 .. 0xFF){
    is(Math::BigInt->new(42),     42);
    is(Math::BigInt->new(42) + 1, 43);
    is(Math::BigInt->new(42) - 1, 41);

    is(Math::BigInt->new(42) * 2, 84);
    is(Math::BigInt->new(42) / 2, 21);

    like(Dumper({ foo => [42]}), qr/\b 42 \b/xms);

    is(basename(__FILE__), '02_more.t');
}

done_testing;
