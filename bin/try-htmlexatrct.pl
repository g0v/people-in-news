use v5.28;
use strict;
use Sn::HTMLExtractor;

use Mojo::UserAgent;

my $url = @ARGV[0] or die;

my $ua = Mojo::UserAgent->new->max_redirects(10);
my $tx = $ua->get($url);

my $ex = Sn::HTMLExtractor->new( html => $tx->res->body );
say $ex->title;
say "========";
say "\n" . $ex->content_text;
