#!/usr/bin/env perl
use v5.18;
use strict;
use warnings;
use Getopt::Long qw(GetOptions);
# use File::Glob ':bsd_glob';
use Mojo::URL;

use Sn;
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

my $yyyymmdd_now = Sn::yyyymmdd_now();
my @dates = grep { $_ ne $yyyymmdd_now } map { /articles-([0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9])\.jsonl\.gz$/ ? $1 : () } glob($opts{db} . '/articles-*.jsonl.gz');

for my $date (@dates) {
    my $fn_stats_all = $opts{o} . "/dailystats-ALL-${date}.tsv";
    next if -f $fn_stats_all;

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

        my $host = Mojo::URL->new( $article->{url} )->host;
        $stats{URLHOST}{$host}++;
    }

    open my $ofh_all, '>:utf8', $fn_stats_all;
    for my $category ( keys %stats ) {
        open my $ofh, '>:utf8', $opts{o} . "/dailystats-${category}-${date}.tsv";
        for my $s (sort { $stats{$category}{$b} <=> $stats{$category}{$a} } keys %{$stats{$category}}) {
            my $line = join("\t", $s, $stats{$category}{$s}) . "\n";
            print $ofh $line;
            print $ofh_all $line;
        }
        close($ofh);
    }
    close($ofh_all);
}
