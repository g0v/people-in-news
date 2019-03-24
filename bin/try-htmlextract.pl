use v5.28;
use strict;
use Sn;
use Sn::HTMLExtractor;
use Sn::ArticleExtractor;
use Encode qw(encode decode);
use Mojo::UserAgent;

my $url = @ARGV[0] or die;

my $tx = Sn::ua()->get($url);
my $article = Sn::ArticleExtractor->new( tx => $tx )->extract;
Sn::print_full_article( \*STDOUT, $article );
