#!/usr/bin/env perl
use Test2::V0;
use FindBin '$Bin';
use File::Next;

use Sn::LineIterator;

my $iter = Sn::LineIterator->new(
    files => Sn::FileIterator->new(
        dir => $Bin . '/db/Sn-line-iterator/',
    )
);

my $count = 0;
while (defined(my $line = $iter->())) {
    $count++;
}

is $count, 7;
done_testing;
