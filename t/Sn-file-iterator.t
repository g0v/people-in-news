#!/usr/bin/env perl
use Test2::V0;
use FindBin '$Bin';
use File::Next;

use Sn::FileIterator;

my $iter = Sn::FileIterator->new(
    dir => ($Bin . '/db/Sn-line-iterator/'),
);

my $count = 0;
while (my $line = $iter->()) {
    $count++;
}

is $count, 2;
done_testing;
