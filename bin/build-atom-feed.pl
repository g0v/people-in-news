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

use Sn;
use Sn::ArticleIterator;

use constant TWO_HOURS_AGO => time - 7200;

sub produce_atom_feed {
    my ($articles, $output) = @_;

    my $feed = XML::FeedPP::Atom::Atom10->new(
        title => "Articles",
    );

    my $now = time();
    for my $article (@$articles) {
        my $item = $feed->add_item(
            link => $article->{url},
            title => $article->{title},
        );
        if (defined $article->{content_text}) {
            $item->set_value(content => markdown($article->{content_text}), type => "html");
        }

        if ($article->{dateline} && (my $t = Sn::parse_dateline($article->{dateline}))) {
            $item->pubDate($t);
        } else {
            $item->pubDate($now);
        }

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

    $feed->to_file( $output );
}

sub summarize {
    my ($text) = @_;

    my @paragraphs = split /\n\n+/, $text;
    return $text if @paragraphs < 2;

    return join "\n\n", @paragraphs[0, -1];
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

my $iter = Sn::ArticleIterator->new(
    db_path => $opts{db},
    filter_file => sub { /\.jsonl$/ },
);

my %seen;
my @articles;
while ( my $article = $iter->() ) {
    next unless defined($article->{t_fetched}) && $article->{t_fetched} > TWO_HOURS_AGO && !( $seen{$article->{url}}++ );
    push @articles, $article;
}
%seen = ();

produce_atom_feed(
    [ map { my %a = %$_; delete $a{content_text}; \%a } @articles ],
    $opts{o} . "/articles-links.atom",
);

produce_atom_feed(
    [ map { my %a = %$_; $a{content_text} = summarize($a{content_text}); \%a } @articles ],
    $opts{o} . "/articles-summarized.atom",
);

produce_atom_feed(
    \@articles,
    $opts{o} . "/articles-full.atom",
);
