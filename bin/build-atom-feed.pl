#!/usr/bin/env perl
use v5.26;
use utf8;
use warnings;

use File::Basename qw(basename);
use Getopt::Long qw(GetOptions);
use Text::Markdown::Discount qw(markdown);
use Encode qw(decode_utf8 encode_utf8);
use File::Slurp qw(read_file write_file);
use JSON qw(decode_json);
use List::Util qw(uniq shuffle);
use URI;
use URI::Escape qw(uri_escape_utf8);
use Try::Tiny;
use XML::FeedPP;
use Time::Moment;

use Sn;
use Sn::ArticleIterator;

sub produce_atom_feed {
    my ($articles, $output, $feed_opts) = @_;

    my $feed = XML::FeedPP::Atom::Atom10->new(
        title => "Articles",
        %$feed_opts,
    );

    my $now = time();
    for my $article (@$articles) {
        my $item = $feed->add_item(
            link => $article->{url},
            title => $article->{title},
        );

        if ($article->{journalist}) {
            $item->author( $article->{journalist} );
        }

        if (defined $article->{content_text}) {
            $item->set_value(content => markdown($article->{content_text}), type => "html");
        }

        if (my $t = $article->{dateline_parsed}) {
            $item->pubDate( $t->epoch );
        } else {
            $item->pubDate( $now );
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

sub looks_good {
    my ($article) = @_;
    defined($article->{dateline})           &&
    defined($article->{journalist})         &&
    defined($article->{content_text})       &&
    defined($article->{title})              &&
    length($article->{content_text}) > 140  &&
    length($article->{title}) > 4
}

sub looks_perfect {
    my ($article) = @_;
    return 0 unless looks_good($article);

    my $substrs = $article->{substrings};

    # people + {event|things} + {taiwan-subdivisions|countries},
    return 0 unless $substrs->{people} && @{ $substrs->{people} } > 0;
    return 0 unless @{$substrs->{event} ||[]} > 0 || @{$substrs->{things} ||[]} > 0 ;
    return 0 unless @{$substrs->{countries} ||[]} > 0 || @{$substrs->{'taiwan-subdivisions'} ||[]} > 0 ;
    return 0 if $article->{title} =~ /網友/;
    return 0 if $article->{content_text} =~ /網友/;

    return 1;
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

my $iter = Sn::ArticleIterator->new(
    db_path => $opts{db},
    filter_file => sub { /\.jsonl$/ },
);

my $now = Time::Moment->now;
my %seen;
my @articles;
while ( my $article = $iter->() ) {
    next unless defined($article->{t_fetched}) && !( $seen{$article->{url}}++ );
    push @articles, $article;

    if ($article->{dateline} && (my $t = Sn::parse_dateline($article->{dateline}))) {
        $article->{dateline_parsed} = $t;
    } else {
        $article->{dateline_parsed} = $now;
    }
}
%seen = ();

@articles = grep {
    my $digest = $_->{title} . "\n" . $_->{content_text};

    ! $seen{$digest}++;
} sort {
    $b->{dateline_parsed}->compare( $a->{dateline_parsed} ) ||  length($a->{url}) <=> length($b->{url})
} @articles;

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

# The maximum is 8, because we have 8 files named "etc/substr-*.txt"
for my $score (0..8) {
    produce_atom_feed(
        +[
            grep {
                $score == keys(%{ $_->{substrings} })
            } @articles,
        ],
        $opts{o} . "/articles-score-${score}.atom",
        +{
            title => "Articles scored ${score}",
        }
    );
}
produce_atom_feed(
    +[ grep { looks_good($_) } @articles ],
    $opts{o} . "/articles-good.atom",
    +{
        title => "Articles (Good)",
    }
);

produce_atom_feed(
    +[ grep { ! looks_good($_) } @articles ],
    $opts{o} . "/articles-ng.atom",
    +{
        title => "Articles (NG)",
    }
);

produce_atom_feed(
    +[ grep { looks_perfect($_) } @articles ],
    $opts{o} . "/articles-subjectively-perfect.atom",
    +{
        title => "Articles (Subjectively Perfect)",
    }
);

produce_atom_feed(
    +[ grep { ! $_->{journalist} } @articles ],
    $opts{o} . "/articles-noauthor.atom",
    +{
        title => "Articles (No Author)",
    }
);

my %articles_by_news_source;
for my $it (@articles) {
    my $x = URI->new($it->{url})->host;
    $x =~ s/\.(tw|pl|jp|uk|ee|cn|cc|fr|hk|io|me|nl)$//;
    $x =~ s/\.(com|org|net|edu|gov|co|ne|or)$//;
    $x =~ s/.+\.([^\.]+)$/$1/;
    push @{$articles_by_news_source{$x}}, $it;
}
for my $it (keys %articles_by_news_source) {
    produce_atom_feed(
        +[ @{$articles_by_news_source{$it}} ],
        $opts{o} . "/articles-news-source-${it}.atom",
        +{ title => "Articles from $it" }
    );
}
%articles_by_news_source = ();

my %articles_by_keyword;
for my $it (@articles) {
    for my $k (keys %{ $it->{substrings} }) {
        for my $x (@{ $it->{substrings}{$k} }) {
            push @{$articles_by_keyword{$x}}, $it;
        }
    }
}
for my $it (keys %articles_by_keyword) {
    my $out = $opts{o} . "/articles-keyword-" . uri_escape_utf8($it) . ".atom";
    produce_atom_feed(
        +[ @{$articles_by_keyword{$it}} ],
        $out,
        +{ title => "Articles mentioned: $it" }
    );
}
