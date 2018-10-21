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

    my $feed = XML::FeedPP::Atom::Atom10->new(
        title => "Articles",
    );

    say "$output <= " . join(" ", @$input);

    for my $input (@$input) {
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
    }

    unlink($output);
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
    my ($ts) = basename($input) =~ m/articles-([0-9]{14})\.jsonl\z/g;
    $ts ? +{ input => $input, ts => $ts } : ()
} grep {
    (stat($_))[7] > 0
} glob("$opts{db}/articles-*.jsonl");

if (@things) {
    build_atom_feed({
        input => [map { $_->{input} } @things],
        output => $opts{o} . "/articles-latest.atom",
    });
}
