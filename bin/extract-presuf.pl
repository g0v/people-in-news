#!/usr/bin/env perl
use Sn;
use Sn::ArticleIterator;

use Getopt::Long qw< GetOptions >;
use Encode qw< encode_utf8 >;
use Text::Util::Chinese qw< presuf_iterator >; ;

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

my $threshold = $opts{threshold} || 42;      # an arbitrary choice.

open my $fh_out, '>', $opts{db} . "/presuf.txt";
my $iter = presuf_iterator(
    sub {
        if (my $article = $articles->next) {
            return $article->{content_text};
        }
        return undef;
    },
    +{
        threshold => $threshold,
    }
);

while(defined(my $tok = $iter->())) {
    say $fh_out encode_utf8("$tok");
}
