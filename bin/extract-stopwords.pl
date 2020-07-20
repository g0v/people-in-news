#!/usr/bin/env perl
use Sn;
use Sn::ArticleIterator;

use List::Util qw(uniq);
use Encode qw(encode_utf8);
use Getopt::Long qw(GetOptions);
use Text::Util::Chinese qw< phrase_iterator >; ;

sub looks_ok {
    my ($phrase) = @_;
    return length($phrase) > 14 && $phrase =~ /\A\p{Han}+\z/;
}

my (%freq, %doc_freq);
sub learn {
    my ($phrase) = @_;
    my @chars = split(//, $phrase);
    $freq{$_}++ for @chars;
    $doc_freq{$_}++ for uniq(@chars);
}

sub top1percent {
    my ($freq) = @_;
    my @elems = sort { $freq->{$b} <=> $freq->{$a} } (keys %$freq);
    @elems = @elems[0.. (0.01*@elems)];
    return { map { $_ => 1 } @elems };
}

sub report {
    # The union of Top 10% from %doc_freq and Top 10% from %%freq
    my $c1 = top1percent(\%doc_freq);
    my $c2 = top1percent(\%doc_freq);

    my %ret = map { $_ => 1 } grep { $c1->{$_} && $c2->{$_} } ((keys %$c1), (keys %$c2));
    my @stopwords = keys %ret;
    for my $c (@stopwords) {
        say encode_utf8(join "\t", $c, $freq{$c}, $doc_freq{$c});
    }
}

# main

my %opts;
GetOptions(
    \%opts,
    "db|d=s"
);
die "--db <DIR> is needed" unless $opts{db} && -d $opts{db};

my $articles = Sn::ArticleIterator->new(
    db_path => $opts{db},
    filter_file => sub { /\.jsonl.gz$/ });

my $phrases = phrase_iterator(
    sub {
	my $article;
	return ( ($article = $articles->next) ? $article->{content_text} : undef );
    });

my $count = 0;
while (my $phrase = $phrases->()) {
    next unless looks_ok($phrase);
    if ( looks_ok( $phrase ) ) {
        learn($phrase);
    }
}

report();
