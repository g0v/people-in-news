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
use List::Util qw(uniq shuffle);

sub build_atom_feed {
    my $input = $_[0]->{input};
    return unless $input;

    my $feed = XML::FeedPP::Atom::Atom10->new(
        title => "Articles",
    );

    my (%freq, @articles);
    for my $input (@$input) {
        open my $fh, '<', $input;
        my $line_num = 0;
        while (<$fh>) {
            $line_num++;
            chomp;
            my $article = try { decode_json($_) };
            unless ($article) {
                say STDERR "decode_json failed at: $input line $line_num";
                next;
            }

            next if $freq{url}{$article->{url}}++;

            $freq{title}{$article->{title}}++;
            $freq{content_text}{$article->{content_text}}++;
            push @articles, $article;
        }
        close($fh);
    }

    @articles = shuffle grep { $freq{title}{$_->{title}} == 1 && $freq{content_text}{$_->{content_text}} == 1 } @articles;

    for my $article (@articles) {
        my $item = $feed->add_item(
            link => $article->{url},
            title => $article->{title},
        );
        $item->set_value(content => markdown($article->{content_text}), type => "html");

        my @categories;
        for (keys %{$article->{substrings}}) {
            for (@{$article->{substrings}{$_}}) {
                push @categories, $_;
            }
        }
        if (@categories) {
            @categories = uniq(@categories);
            $item->category(\@categories);
        }
    }

    return $feed;
}

sub write_atom_feed {
    my $feed = build_atom_feed(@_);
    my $output = $_[0]->{output};
    unlink($output) if -f $output;
    $feed->to_file($output);
}

sub write_atom_feed_link_only {
    my $feed = build_atom_feed(@_);
    my $output = $_[0]->{output};

    my $i = 0;
    while (my $item = $feed->get_item($i++) ) {
        delete $item->{content};
    }

    unlink($output) if -f $output;
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
    write_atom_feed({
        input => [map { $_->{input} } @things],
        output => $opts{o} . "/articles-latest.atom",
    });

    write_atom_feed_link_only({
        input => [map { $_->{input} } @things],
        output => $opts{o} . "/articles-latest-link-only.atom",
    });
}
