#!/usr/bin/env perl
use v5.26;
use utf8;
use warnings;

use Getopt::Long qw(GetOptions);
use Text::Markdown::Discount qw(markdown);
use List::Util qw(uniq);
use Time::Moment;
use XML::FeedPP;

use Sn;
use Sn::ArticleIterator;

sub remove_if(&$) {
    my ($condition, $arr) = @_;
    my $goner = [];
    for (my $i = 0; $i < @$arr; $i++) {
        local $_ = $arr->[$i];
        if (defined($_) && $condition->()) {
            push @$goner, $arr->[$i];
            $arr->[$i] = undef;
        }
    }
    return $goner;
}

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

        my @categories = map { @{$article->{substrings}{$_}} } (keys %{$article->{substrings}});

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
    length($article->{title}) > 4           &&
    length($article->{journalist}) > 0      &&
    length($article->{dateline}) > 0        &&
    length($article->{content_text}) > length($article->{title})
}

sub contains_keywords {
    my ($article) = @_;
    my $substrs = $article->{substrings};

    my $has_keywords = 0;
    for my $k (keys %$substrs) {
        if (@{ $substrs->{$k} }) {
            $has_keywords++;
            last;
        }
    }

    return $has_keywords;
}

sub looks_buggy {
    my ($article) = @_;

    my $substrs = $article->{substrings};

    return 1 if @{ $substrs->{"common-typos"} //[] };

    my @buggy_keywords = qw( 網友 臉書社團 靈異公社 爆廢公社 爆料公社 爆怨公社 PTT );
    my $re = '(?:' . join('|', map { "\Q$_\E" } @buggy_keywords) . ')';
    return 1 if ($article->{title} =~ /$re/io || $article->{content_text} =~ /$re/io);

    return 0;
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

my $epoch_zero = Time::Moment->from_epoch(0);
my %seen;
my @articles;
while ( my $article = $iter->() ) {
    next unless defined($article->{t_fetched}) && !( $seen{$article->{url}}++ );
    push @articles, $article;

    if ($article->{dateline} && (my $t = Sn::parse_dateline($article->{dateline}))) {
        $article->{dateline_parsed} = $t;
    } else {
        $article->{dateline_parsed} = $epoch_zero;
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
    (remove_if { ! looks_good($_) } \@articles),
    $opts{o} . "/articles-ng.atom",
    +{
        title => "Articles (NG)",
    }
);

produce_atom_feed(
    (remove_if { looks_buggy($_) } \@articles),
    $opts{o} . "/articles-buggy.atom",
    +{
        title => "Articles (Buggy)",
    }
);

produce_atom_feed(
    (remove_if { ! contains_keywords($_) } \@articles),
    $opts{o} . "/articles-nokeywords.atom",
    +{
        title => "Articles (No Keywords)",
    }
);

produce_atom_feed(
    \@articles,
    $opts{o} . "/articles.atom",
    +{
        title => "Articles",
    }
);
