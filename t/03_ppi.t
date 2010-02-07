#!perl -w

use strict;
use optimizer::hotspot;

use Test::Requires 'PPI';
use Test::More;

for(1 .. 100){
    my $doc = PPI::Document->new($0);

    ok $doc, 'PPI::Document->new';
    ok $doc->serialize, 'serialize';
}

done_testing;
