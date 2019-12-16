use v5.18;
use warnings;
use Test2::V0;
use Importer 'Sn::TextUtil' => qw(looks_like_similar_host);

my @positive_tests = (
    ['uuu.co.jp', 'www.uuu.co.jp'],
    ['xyz.com', 'xyz.com'],
    ['www.xxx.com.tw', 'news.xxx.com.tw'],
    ['example.org', 'www.example.org'],
    ['example.org', 'xxx.www.example.org'],
    ['vvv.example.org', 'xxx.www.example.org'],
);

my @negative_tests = (
    ['xyz.co.jp', 'yyy.co.jp'],
    ['xyz.com', 'yzx.com'],
    ['www.xxx.com.tw', 'news.xyz.com.tw'],
    ['xxx.org', 'yyy.org'],
    ['xxx.org', 'xxx.yyy.org'],
);

subtest "Positive tests" => sub {
    for my $t ( @positive_tests ) {
        my $r = looks_like_similar_host(@$t);
        ok $r, join(" vs ", @$t);
    }
};

subtest "Negativ tests" => sub {
    for my $t ( @negative_tests ) {
        my $r = ! looks_like_similar_host(@$t);
        ok $r, join(" vs ", @$t);
    }
};

done_testing;
