#!/usr/bin/env perl
use v5.26;
use strict;
use warnings;

use Getopt::Long qw(GetOptions);
use Try::Tiny;
use File::Basename qw(basename);
use Encode qw(encode_utf8 decode_utf8);
use Getopt::Long qw(GetOptions);

use List::Util qw(maxstr);
use Path::Tiny qw(path);

use Sn;
use Sn::Seen;
use Sn::Extractor;
use Sn::ArticleIterator;

sub load_substrs {
    my %substrs;

    $substrs{people} = [
        @{ Sn::load_substr_file('etc/substr-political-people.txt') },
        @{ Sn::load_substr_file('etc/substr-powerful-people.txt') },
    ];
    
    $substrs{places} = [
        @{ Sn::load_substr_file('etc/substr-countries.txt') },
        @{ Sn::load_substr_file('etc/substr-taiwan-subdivisions.txt') },
    ];
    $substrs{events} = Sn::load_substr_file('etc/substr-events.txt');
    $substrs{things} = Sn::load_substr_file('etc/substr-things.txt');

    return %substrs;
}

my %opts;
GetOptions(
    \%opts,
    "db=s",
);
die "--db <DIR> is needed" unless -d $opts{db};

my %substrs = load_substrs();

my $articles = Sn::ArticleIterator->new(
    db_path => $opts{db},
    filter_file => sub { /\.jsonl.gz$/ },
);

my @all_token_types = qw<places events things people>;
while (my $article = $articles->next) {
    my $content_text = $article->{content_text};

    my %matched;
    for my $type (@all_token_types) {
        for my $token (@{ $substrs{$type} }) {
            my $pos = index($content_text, $token);
            if ($pos >= 0) {
                $matched{$type}{$token} = $pos;
            }
        }
    }

    if (keys %matched > 2) {
        my @hint;
        for my $type (@all_token_types) {
            my @m = keys %{$matched{$type}};
            @m = ('') unless @m;
            @m = sort @m;
            push @hint, $type . ':' . join(",",  @m);
        }

        if (@hint) {
            say encode_utf8(
                join(' / ', @hint) . "\n" .
                "- " . $article->{title} . "\n" .
                "- " . $article->{url} . "\n" .
                "----"
            );
        }
    }
}
