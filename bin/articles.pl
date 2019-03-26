#!/usr/bin/env perl
use v5.26;
use strict;
use warnings;

use Getopt::Long qw< GetOptions >;
use Encode qw< encode_utf8 >;
use JSON qw< encode_json >;
use Text::Util::Chinese qw< extract_presuf >; ;

use Sn;
use Sn::ArticleIterator;

my %opts;
GetOptions(
    \%opts,
    "db=s",
);
die "--db <DIR> is needed" unless $opts{db} && (-d $opts{db} || -f $opts{db});

my $articles = Sn::ArticleIterator->new(
    db_path => $opts{db},
    filter_file => sub { /\.jsonl.gz$/ },
);

my $count = 0;
binmode STDOUT;
while (my $article = $articles->()) {
    Sn::print_full_article(\*STDOUT, $article);
}
say "Count: $count";
