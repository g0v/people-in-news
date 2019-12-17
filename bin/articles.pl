#!/usr/bin/env perl
use v5.26;
use strict;
use warnings;

use Getopt::Long qw< GetOptions >;
use Encode qw< decode_utf8 >;

 ;

use Sn;
use Sn::ArticleIterator;

my %opts;
GetOptions(
    \%opts,
    "db=s",
    "q=s@",
);
die "--db <DIR> is needed" unless $opts{db} && (-d $opts{db} || -f $opts{db});

my $articles = Sn::ArticleIterator->new(
    db_path => $opts{db},
    filter_file => sub { /\.jsonl.gz$/ },
);

my @query = map {
    join '|', map { "\Q$_\E" } split /\s+/, decode_utf8($_)
} @{ $opts{q} //[]};

my $count = 0;
binmode STDOUT;

if (@query) {
    while (my $article = $articles->()) {
        my $matches = 0;
        for my $re (@query) {
            last unless (
                $article->{title}        =~ /$re/ ||
                $article->{content_text} =~ /$re/
            );
            $matches++;
        }
        next if $matches != @query;
        Sn::print_full_article(\*STDOUT, $article);
        $count++;
    }
} else {
    while (my $article = $articles->()) {
        Sn::print_full_article(\*STDOUT, $article);
        $count++;
    }
}
say "Count: $count";
