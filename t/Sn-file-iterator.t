#!/usr/bin/env perl
use Test2::V0;
use FindBin '$Bin';
use File::Next;

use Sn::FileIterator;

subtest 'Take all files', sub {
    my $iter = Sn::FileIterator->new(
        dir => ($Bin . '/db/Sn-line-iterator/'),
    );

    my $count = 0;
    while (my $line = $iter->()) {
        $count++;
    }

    is $count, 2;
};

subtest 'Take some files', sub {
    my $iter = Sn::FileIterator->new(
        dir => ($Bin . '/db/Sn-line-iterator/'),
        filter => sub {
            my ($n) = $_[0] =~ m/(\d+)/;
            return $n % 2 == 0;
        }
    );

    my $count = 0;
    while (my $line = $iter->()) {
        $count++;
    }

    is $count, 1;
};

done_testing;
