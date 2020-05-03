#!/usr/bin/env perl
use v5.26;
use warnings;
use JSON qw(encode_json);

use Sn;
use Sn::ArticleExtractor;

my $url = $ARGV[0];

Sn::urls_get_all(
    [$url],
    sub {
        my ($tx, $url) = @_;
        my $ex = Sn::ArticleExtractor->new( tx => $tx );
        my ($article, $links) = $ex->extract;

        say encode_json({
            article => $article,
            links => $links,
        });
    }
);
