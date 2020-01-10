#!/usr/bin/env perl
use v5.26;
use strict;
use warnings;

use Encode qw(encode_utf8);
use Getopt::Long qw(GetOptions);
use List::Util qw(maxstr);
use String::Trim qw(trim);
use File::Basename qw(basename);

use Sn::ArticleIterator;

sub squeeze {
    my ($str) = @_;
    $str =~ s/\r?\n/ /g;
    $str =~ s/\s+/ /g;
    return trim($str);
}

sub uniq_by(&@) {
    my $cb = shift;
    my %seen;
    my @items;
    for my $item (@_) {
        local $_ = $item;
        my $k = $cb->($item);
        unless ($seen{$k}) {
            $seen{$k} = 1;
            push @items, $item;
        }
    }
    return @items;
}

sub build_md {
    my ($page, $output) = @_;

    my $md = "";
    for my $h1 (sort { $a cmp $b } keys %$page) {
        my $h1_titlized = $h1 =~ s/-/ /gr =~ s/\b(\p{Letter})/uc($1)/ger;

        $md .= "## $h1_titlized\n\n";
        for my $h2 (keys %{$page->{$h1}}) {
            $md .= "### $h2\n\n";
            for my $d (uniq_by { $_->{title} } @{$page->{$h1}{$h2}}) {
                $md .= "- [" . squeeze($d->{title}) . "]($d->{url})\n";
            }
            $md .= "\n";
        }
        $md .= "\n";
    }

    $md =~ s/[^[:print:]\s]//g;

    open my $fh, '>', $output;
    say $fh encode_utf8($md);
    close($fh);
}

## main
my %opts;
GetOptions(
    \%opts,
    "force|f",
    "db=s",
    "o=s",
);
die "--db <DIR> is needed" unless $opts{db} && -d $opts{db};
die "-o <DIR> is needed" unless $opts{o} && -d $opts{o};

my %buckets;
for my $file (glob "$opts{db}/articles-*.jsonl.gz") {
    my ($k) = $file =~ m/ - ([0-9]{8}) ([0-9]{6})? \.jsonl\.gz \z/x;
    next unless $k;
    push @{$buckets{$k}}, $file;
}

my @t = localtime();
my $today = sprintf('%04d%02d%02d', $t[5]+1900, $t[4]+1, $t[3]);
my $daily_today = $opts{o} . "/daily-$today.md";

for my $yyyymmdd (keys %buckets) {
    my @input = @{$buckets{$yyyymmdd}};
    my $output = $opts{o} . "/daily-$yyyymmdd.md";
    next if !$opts{force} && (($output lt $daily_today) && (-f $output));

    my %page;
    my %url_seen;
    my %freq;

    my @articles;
    for my $file (@input) {
        my $iter = Sn::ArticleIterator->new(
            db_path => $opts{db},
            filter_file => sub { $_ eq basename($file) },
        );

        while(defined(my $article = $iter->())) {
            next unless $article->{url};
            next if $url_seen{$article->{url}};

            $url_seen{$article->{url}} = 1;
            next unless (
                $freq{title}{$article->{title}}++ == 0
                && $freq{content_text}{$article->{content_text}}++ == 0
            );

            push @articles, $article;
        }
    }

    @articles = grep { $freq{title}{$_->{title}} == 1 && $freq{content_text}{$_->{content_text}} == 1 } @articles;

    for my $d (@articles) {
        my $substring_count = 0;
        for my $k (keys %{$d->{substrings}}) {
            for (@{$d->{substrings}{$k}}) {
                push @{$page{$k}{$_}}, $d;
                $substring_count++;
            }
        }

        if ($substring_count == 0) {
            push @{$page{"(No Category)"}{"(No Keyword)"}}, $d;
        }
    }
    
    build_md(\%page, $output);
}

my $new_index = maxstr( glob "$opts{o}/daily-*.md" );
if ($new_index) {
    unlink("$opts{o}/Home.md");
    link($new_index, "$opts{o}/Home.md");
}
