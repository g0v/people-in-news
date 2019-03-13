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
);
die "--db <DIR> is needed" unless -d $opts{db};

my $articles = Sn::ArticleIterator->new(
    db_path => $opts{db},
    filter_file => sub { /\.jsonl.gz$/ },
);

my $count = 0;
my %stats;
my %extracted;

while (my $article = $articles->next) {
    my $text = $article->{content_text};
    my @stuff = split /\p{General_Category: Other_Punctuation}+/, $text;
    for my $phrase (@stuff) {
        for my $len (2..5) {
            my $re = '\p{Block: CJK}{' . $len . '}';
            next unless length($phrase) > $len * 2 && $phrase =~ /\A($re) .+ ($re)\z/x;
            my ($prefix, $suffix) = ($1, $2);
            $stats{prefix}{$prefix}++ unless $extracted{$prefix};
            $stats{suffix}{$suffix}++ unless $extracted{$suffix};
        }
    }

    if ($count++ > 9999) {
        my $threshold = 9;      # an arbitrary choice.
        for my $x (keys %{$stats{prefix}}) {
            next unless $stats{prefix}{$x} > $threshold;
            next unless $stats{suffix}{$x} && $stats{suffix}{$x} > $threshold;
            $extracted{$x} = 1;

            delete $stats{prefix}{$x};
            delete $stats{suffix}{$x};

            say encode_utf8($x);
        }
        $count = 0;
    }
}



