#!/usr/bin/env perl
use v5.26;
use warnings;

use List::Util qw< uniqstr >;
use File::Basename qw< basename >;
use Getopt::Long qw< GetOptions >;
use JSON ();
use PerlIO::via::gzip;
use URI;
use Sn;
use Sn::ArticleIterator;

## helpers
sub looks_empty {
    my $s = $_[0];
    return 1 unless defined($s);
    return 1 if length($s) == 0;
    return 1 if $s =~ /\A\s+\z/u;
    return 0;
}

## main

my %opts;
GetOptions(
    \%opts,
    "db=s",
);
die "--db <DIR> is needed" unless $opts{db} && (-d $opts{db} || -f $opts{db});

my $json = JSON->new->canonical->utf8;

for my $file (<$opts{db}/articles-*.jsonl.gz>) {
    say "# Processing: $file";

    my $articles = Sn::ArticleIterator->new(
        db_path => $opts{db},
        filter_file => sub { $_ eq basename($file) },
    );

    my $output_temp = $opts{db} . '/' . ".cleanup-" . basename($file);

    open my $fh, '>:via(gzip)', $output_temp;

    while (my $article = $articles->()) {
        my $uri = URI->new($article->{url});

        # The "root" pages are never a permalink of any NewsArticle
        next if $uri->path eq '/';

        # Sanity checks.
        next if looks_empty($article->{title}) || looks_empty($article->{content_text});

        # Some old records contains duplicate keywords.
        my $o = $article->{substrings};
        for my $k (keys %$o) {
            $o->{$k} = [sort { $a cmp $b } uniqstr(@{ $o->{$k} })];
        }

        say $fh $json->encode($article);
    }
    close($fh);

    unlink($file);
    link($output_temp, $file);
    unlink($output_temp);
}
