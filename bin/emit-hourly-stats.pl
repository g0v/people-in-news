#!/usr/bin/env perl
use v5.18;
use strict;
use warnings;


use Getopt::Long qw(GetOptions);
use Mojo::URL;
use Mojo::Util qw(url_escape);
use Net::Graphite;

use Sn;
use Sn::ArticleIterator;


sub graphite_metric_escape {
    my $s = $_[0];
    $s =~ s/\./-/g;
    $s = url_escape($s);
    return $s;
}

## main
my %opts;
GetOptions(
    \%opts,
    "db=s",
);
die "--db <DIR> is needed" unless -d $opts{db};

my $yyyymmdd_now = Sn::yyyymmdd_now();

my $articles = Sn::ArticleIterator->new(
    db_path => $opts{db},
    filter_file => sub { /-${yyyymmdd_now}\.jsonl$/ }
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

my $graphite = Net::Graphite->new( host => '127.0.0.1' );
for my $category ( keys %stats ) {
    for my $s (keys %{$stats{$category}}) {
        my $metric = join '.', qw(hourly csum substr-in-news), $category, graphite_metric_escape($s);
        $graphite->send(
            path => $metric,
            value => $stats{$category}{$s},
        );
        say STDERR "$metric $stats{$category}{$s}";
    }
}
