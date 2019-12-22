#!/usr/bin/env perl
use Test2::V0;
use FindBin '$Bin';
use File::Next;

use Sn::LineIterator;
use Sn::FileIterator;

subtest 'Take all lines from all files', sub {
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
};

subtest 'Take lines from somes files', sub {
    my $iter = Sn::LineIterator->new(
        files => Sn::FileIterator->new(
            dir => $Bin . '/db/Sn-line-iterator/',
            filter => sub { /2/ },
        )
    );

    my $count = 0;
    while (defined(my $line = $iter->())) {
        $count++;
    }

    is $count, 4;
};


done_testing;
