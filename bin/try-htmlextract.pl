use v5.28;
use strict;
use Sn;
use Sn::FFUA;
use Sn::HTMLExtractor;
use Sn::ArticleExtractor;
use Encode qw(encode decode);
use Mojo::UserAgent;
use Getopt::Long qw< GetOptions >;

my %opts;
GetOptions(
    \%opts,
    "firefox",
);

my $url = shift @ARGV or die;

my $tx;
if ($opts{firefox}) {
    $tx = Sn::FFUA->new->fetch($url);
} else {
    $tx = Sn::ua()->get($url);
}

my $article = Sn::ArticleExtractor->new( tx => $tx )->extract;
Sn::print_full_article( \*STDOUT, $article );
