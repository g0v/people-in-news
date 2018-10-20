#!/usr/bin/env perl
use v5.26;
use strict;
use warnings;
use File::Basename qw(basename);
use Getopt::Long qw(GetOptions);
use Text::Markdown::Discount qw(markdown);
use Encode qw(decode_utf8 encode_utf8);
use File::Slurp qw(read_file write_file);
use JSON qw(decode_json);
use Try::Tiny;
use MCE::Loop;
use XML::FeedPP;

sub build_atom_feed {
    my $input = $_[0]->{input};
    my $output = $_[0]->{output};

    return unless $input && $output;

    say "$input => $output";

    my $feed = XML::FeedPP::Atom::Atom10->new(
        title => "Articles",
    );

    open my $fh, '<', $input;
    while (<$fh>) {
        chomp;
        my $article = try { decode_json($_) } or next;
        my $item = $feed->add_item(
            link => $article->{url},
            title => $article->{title},
        );
        $item->set_value(content => $article->{content_text}, type => "text");

        my @categories;
        for (keys %{$article->{substrings}}) {
            for (@{$article->{substrings}{$_}}) {
                push @categories, $_;
            }
        }
        if (@categories) {
            $item->category(\@categories);
        }
    }

    $feed->to_file($output);
}

## main
my %opts;
GetOptions(
    \%opts,
    "force|f",
    "db=s",
    "o=s",
);
die "--db <DIR> is needed" unless -d $opts{db};
die "-o <DIR> is needed" unless -d $opts{o};

my @things = map {
    my $input = $_;
    my ($ts) = basename($input) =~ m/articles-(\d+)\.jsonl\z/g;
    +{ input => $input, ts => $ts }
} grep {
    (stat($_))[7] > 0
} glob("$opts{db}/articles-*.jsonl");

my $latest = $things[0];
for (@things) {
    if ($_->{ts} > $latest->{ts}) {
        $latest = $_;
    }
}

$latest->{output} = $opts{o} . "/articles-latest.atom";
build_atom_feed($latest);
