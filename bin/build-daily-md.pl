#!/usr/bin/env perl
use v5.26;
use strict;
use warnings;
use File::Basename qw(basename);
use Encode qw(encode_utf8 decode_utf8);
use Getopt::Long qw(GetOptions);
use JSON qw(decode_json);
use List::Util qw(maxstr);
use Try::Tiny;

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
                $d->{title} =~ s/\A\s+//;
                $d->{title} =~ s/\s+\z//;
                $md .= "- [$d->{title}]($d->{url})\n";
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
for my $file (glob "$opts{db}/articles-*.jsonl") {
    my ($k) = $file =~ m/ - ([0-9]{8}) ([0-9]{6})? \.jsonl \z/x;
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
    my %title_freq;

    my @articles;
    for my $file (@input) {
        open my $fh, '<', $file;

        while (<$fh>) {
            chomp;
            next unless /\A\{/ && /\}\z/;
            my $d = try { decode_json($_) } or next;
            next unless $d->{url};
            next if $url_seen{$d->{url}};
            $url_seen{$d->{url}} = 1;

            unless ($title_freq{$d->{title}}++) {
                push @articles, $d;
            }
        }
        close($fh);
    }

    @articles = grep { $title_freq{$_->{title}} == 1 } @articles;

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
unlink("$opts{o}/Home.md");
link($new_index, "$opts{o}/Home.md");
