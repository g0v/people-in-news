#!/usr/bin/env perl
use v5.26;
use strict;
use warnings;

use Getopt::Long qw< GetOptions >;
use Encode qw< decode_utf8 >;

use Sn;
use Sn::ArticleIterator;

my %opts;
GetOptions(
    \%opts,
    "mbox",
    "limit=n",
    "db=s",
    "q=s@",
    "without-journalist",
    "without-dateline",
);
die "--db <DIR> is needed" unless $opts{db} && (-d $opts{db} || -f $opts{db});

my $articles = Sn::ArticleIterator->new(
    db_path => $opts{db},
    filter_file => sub { /\.jsonl.gz$/ },
);

my @query = map {
    join '|', map { "\Q$_\E" } split /\s+/, decode_utf8($_)
} @{ $opts{q} //[]};

binmode STDOUT;

my $count = $opts{limit};
my %seen;

while (my $article = $articles->()) {
    next if $seen{$article->{url}};
    $seen{$article->{url}} = 1;

    next if ((! $article->{dateline} || $opts{'without-dateline'} && $article->{dateline}) or (! $article->{journalist} || $opts{'without-journalist'} && $article->{journalist}));

    my $matches = 0;
    for my $re (@query) {
        last unless (
            $article->{title}        =~ /$re/ ||
            $article->{content_text} =~ /$re/
        );
        $matches++;
    }
    next if @query > 0 && $matches != @query;

    if ($opts{mbox}) {
        Sn::print_article_like_mail(\*STDOUT, $article);
    } else {
        Sn::print_full_article(\*STDOUT, $article);
    }

    last if defined($count) && $count-- == 0;
}
