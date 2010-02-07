#!perl -w

use strict;
use optimizer::hotspot;

use Test::Requires 'Moose' => 0.93;
use Test::More;

{
    package C1;
    use Moose;

    has foo => (
        is => 'ro',
    );

    __PACKAGE__->meta->make_immutable;

    package C2;
    use Moose;

    has foo => (
        is      => 'ro',
        default => 10,
    );

    __PACKAGE__->meta->make_immutable;

    package C3;
    use Moose;

    has foo => (
        is      => 'ro',
        isa     => 'Int',
        default => 10,
    );

    __PACKAGE__->meta->make_immutable;

    package C4;
    use Moose;

    has foo => (
        is      => 'ro',
        isa     => 'Int',
        default => sub{ 10 },
    );

    __PACKAGE__->meta->make_immutable;

    package C5;
    use Moose;

    has foo => (
        is      => 'rw',
        isa     => 'Int',
        lazy_build => 1,
    );

    sub _build_foo{ 10 }

    __PACKAGE__->meta->make_immutable;
}

for(1 .. 100){
    foreach my $class(qw(C1 C2 C3 C4 C5)){
        isa_ok($class->new, $class);
    }
}

done_testing;
