#!/usr/bin/env perl
use v5.18;
use strict;
use warnings;
use Getopt::Long qw(GetOptions);
# use File::Glob ':bsd_glob';

use Sn::ArticleIterator;

## main
my %opts;
GetOptions(
    \%opts,
    "db=s",
    "o=s",
);
die "--db <DIR> is needed" unless -d $opts{db};
die "-o <DIR> is needed" unless -d $opts{o};

my @dates = map { /articles-([0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9])\.jsonl/ ? $1 : () } glob($opts{db} . '/articles-*.jsonl*');

for my $date (@dates) {
    my $articles = Sn::ArticleIterator->new(
        db_path => $opts{db},
        filter_file => sub { /-$date\./ }
    );

    my %stats;
    while (my $article = $articles->next) {
        my $substrings = $article->{substrings};
        for my $category (keys %$substrings) {
            for my $s (@{ $substrings->{$category} }) {
                $stats{$category}{$s}++;
            }
        }
    }

    for my $category ( keys %stats ) {
        open my $ofh, '>:utf8', $opts{o} . "/dailystats-${category}-${date}.tsv";
        for my $s (sort { $stats{$category}{$b} <=> $stats{$category}{$a} } keys %{$stats{$category}}) {
            print $ofh join("\t", $s, $stats{$category}{$s}) . "\n";
        }
        close($ofh);
    }
}
