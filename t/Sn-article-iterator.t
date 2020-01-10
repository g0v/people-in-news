#!/usr/bin/env perl
use Test2::V0;
use FindBin '$Bin';

use Sn::ArticleIterator;

subtest 'Count all articles from all files', sub {
    my $iter = Sn::ArticleIterator->new(
        db_path => $Bin . '/db/Sn-article-iterator/',
    );

    my $count = 0;
    while (defined(my $article = $iter->())) {
        $count++;
    }

    is $count, 9;
};

done_testing;
