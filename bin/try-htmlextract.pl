use v5.28;
use strict;
use Sn;
use Sn::HTMLExtractor;

use Mojo::UserAgent;

my $url = @ARGV[0] or die;

my $tx = Sn::ua()->get($url);
my $charset = Sn::tx_guess_charset($tx) or die "Failed to detect the charset";

my $ex = Sn::HTMLExtractor->new( html => decode($charset, $tx->res->body) );
say $ex->title;
say "========";
say $ex->dateline . "\n";
say "\n" . $ex->content_text;
