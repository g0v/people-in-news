use v5.28;
use strict;
use Sn;
use Sn::FFUA;
use Sn::PhantomJSUA;
use Sn::ChromeUA;
use Sn::HTMLExtractor;
use Sn::ArticleExtractor;
use Encode qw(encode decode);
use Mojo::UserAgent;
use Getopt::Long qw< GetOptions >;

my %opts;
GetOptions(
    \%opts,
    "firefox",
    "chrome",
    "phantomjs",
);

my $url = shift @ARGV or die;

my $tx;
if ($opts{firefox}) {
    $tx = Sn::FFUA->new->fetch($url);
} elsif ($opts{chrome}) {
    $tx = Sn::ChromeUA->new->fetch($url);
} elsif ($opts{phantomjs}) {
    $tx = Sn::PhantomJSUA->new->fetch($url);
} else {
    $tx = Sn::ua()->get($url);
}

my $article = Sn::ArticleExtractor->new( tx => $tx )->extract;

if ($article) {
    Sn::print_full_article( \*STDOUT, $article );
} else {
    print "No Article\n";
}
