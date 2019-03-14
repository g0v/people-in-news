#!/usr/bin/env perl
use v5.26;
use strict;
use warnings;

use Getopt::Long qw(GetOptions);
use JSON::PP qw(encode_json decode_json);
use Try::Tiny;
use Encode qw< encode_utf8 >;
use Text::Util::Chinese qw< extract_presuf >; ;

use Sn;
use Sn::Seen;
use Sn::Extractor;
use Sn::ArticleIterator;

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

extract_presuf(
    sub {
        if (my $article = $articles->next) {
            return $article->{content_text};
        }
        return undef;
    },
    sub {
        my ($txt) = @_;
        say encode_utf8($txt);
    },
    +{
        threshold => $threshold,
    }
);

