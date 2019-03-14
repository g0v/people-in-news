#!/usr/bin/env perl
use v5.26;
use strict;
use warnings;

use Getopt::Long qw(GetOptions);
use JSON::PP qw(encode_json decode_json);
use Try::Tiny;
use Encode qw< encode_utf8 >;

use Sn;
use Sn::Seen;
use Sn::Extractor;
use Sn::ArticleIterator;

my %opts;
GetOptions(
    \%opts,
    "db=s",
    "threshold=n",
);
die "--db <DIR> is needed" unless -d $opts{db};

my $articles = Sn::ArticleIterator->new(
    db_path => $opts{db},
    filter_file => sub { /\.jsonl.gz$/ },
);

my $count = 0;
my %stats;
my %extracted;
my $threshold = $opts{threshold} || 42;      # an arbitrary choice.

while (my $article = $articles->next) {
    my $text = $article->{content_text};
    my @stuff = split /\p{General_Category: Other_Punctuation}+/, $text;
    for my $phrase (@stuff) {
        next unless length($phrase) > 2 && $phrase =~ /\A\p{Han}+\z/x;

        for my $len (2..5) {
            my $re = '\p{Han}{' . $len . '}';
            next unless length($phrase) > $len * 2 && $phrase =~ /\A($re) .+ ($re)\z/x;
            my ($prefix, $suffix) = ($1, $2);
            $stats{prefix}{$prefix}++ unless $extracted{$prefix};
            $stats{suffix}{$suffix}++ unless $extracted{$suffix};

            for my $x ($prefix, $suffix) {
                if (! $extracted{$x} && $stats{prefix}{$x} && $stats{suffix}{$x} && $stats{prefix}{$x} > $threshold && $stats{suffix}{$x} > $threshold) {
                    $extracted{$prefix} = 1;
                    delete $stats{prefix}{$x};
                    delete $stats{suffix}{$x};

                    say encode_utf8($x);
                }
            }
        }
    }
}
