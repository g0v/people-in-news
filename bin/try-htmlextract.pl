use v5.28;
use strict;
use Sn;
use Sn::HTMLExtractor;

use Mojo::UserAgent;

my $url = @ARGV[0] or die;

my $tx = Sn::ua()->get($url);

my $ex = Sn::HTMLExtractor->new( html => $tx->res->body );
say $ex->title;
say "========";
say "\n" . $ex->content_text;
