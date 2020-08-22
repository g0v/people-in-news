#!/usr/bin/env perl
use Test2::V0;
use FindBin '$Bin';

use Sn::IntIterator;
use Sn::FilterIterator;

subtest 'simple IntIterator' => sub {
    my $iter1 = Sn::IntIterator->new(
        from  => 1,
        until => 10,
    );

    my $numbers = $iter1->exhaust;
    is($numbers, [1,2,3,4,5,6,7,8,9]);
};

subtest 'IntIterator with map' => sub {
    my $iter = Sn::IntIterator->new(
        from  => 1,
        until => 10,
    )->map(sub { $_ * $_ });

    my $numbers = $iter->exhaust;
    is($numbers, [1,4,9,16,25,36,49,64,81]);
};


subtest 'Only Odd numbers' => sub {
    my $iter1 = Sn::IntIterator->new(
        from  => 1,
        until => 10,
    );
    my $iter2 = Sn::FilterIterator->new(
        iterator => $iter1,
        reject_if => sub { $_[0] % 2 == 0 }
    );

    my $odd_numbers = $iter2->exhaust;
    is($odd_numbers, [1,3,5,7,9]);
};

done_testing;
