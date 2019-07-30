#!/usr/bin/env perl
use v5.26;
use strict;
use warnings;

use URI;
use Try::Tiny;
use MCE::Loop;
use Mojo::UserAgent;
use Mojo::Promise;
use HTML::ExtractContent;
use Encode qw(encode_utf8 decode);
use Encode::Guess;
use Getopt::Long qw(GetOptions);
use Algorithm::BloomFilter;

use List::Util qw(uniqstr max shuffle);
use JSON ();
use FindBin '$Bin';

use Sn;
use Sn::Seen;
use Sn::Extractor;
use Sn::HTMLExtractor;
use Sn::ArticleExtractor;
use Sn::FTVScraper;

use constant CUTOFF => $ENV{CUTOFF} || 999;

## global
my $PROCESS_START = time();
my $STOP = 0;
local $SIG{INT} = sub { $STOP = 1 };

sub err {
    say STDERR @_;
}

sub encode_article_as_json {
    state $json = JSON->new->utf8->canonical;
    $json->encode($_[0]);
}

sub looks_like_similar_host {
    my @host = map { s/.+\.([^\.]+)$/$1/r } map { s/\.((com|org|net)(\.tw)?|(co|ne|or)\.(jp|uk))$//r } @_;
    return $host[0] eq $host[1]
}

sub looks_like_xml {
    my ($url) = @_;
    return $url =~ m{ \com/tag/(?:.+)\.xml \z};
}

sub process_generic {
    my ($url, $url_seen, $out) = @_;

    say "[$$] Process generically: $url";

    open my $fh, '>', $out;
    $fh->autoflush(1);

    my $error_count = 0;
    my $extracted_count = 0;

    my @links = ($url);
    my %seen = map { $_ => 1 } @links;

    my $round = 0;
    while (!$STOP && @links && $round++ < 3) {
        $STOP = 1 if time() - $PROCESS_START > 1200;

        my (@discovered_links, @processed_links);

        say "[$$] TODO: " . (0 + @links) . " urls";
        Sn::urls_get_all(
            \@links,
            sub {
                my ($tx, $url) = @_;
                my $host_old = URI->new($url)->host;
                my $article = Sn::ArticleExtractor->new( tx => $tx )->extract;

                if ($article) {
                    for my $url_new (@{$article->{links} //[]}) {
                        my $host_new = URI->new($url_new)->host;
                        unless ($seen{$url_new} || !looks_like_similar_host($host_new, $host_old) || looks_like_xml($url_new) ) {
                            push @discovered_links, $url_new;
                            $seen{$url_new} = 1;
                        }
                    }
                    delete $article->{links};

                    if ($article->{title}) {
                        my $line = encode_article_as_json($article) . "\n";
                        print $fh $line;
                        $extracted_count++;
                        push @processed_links, $url;
                    }
                } else {
                    say "[$$] Fail to extract from $url";
                }
                return ($STOP || ($extracted_count > CUTOFF)) ? 0 : 1;
            },
            sub {
                my ($error, $url) = @_;
                say STDERR "ERROR:\t$error\t$url";
                return $STOP ? 0 : 1;
            }
        );

        if (@processed_links) {
            MCE->do('add_to_url_seen', \@processed_links);
        }

        @links = grep { ( ! m{^https://twitter.com/} ) && (! $url_seen->test("$_")) } @discovered_links;
    }

    close($fh);
}

sub process_ftv {
    my ($url_seen, $out) = @_;

    say "[$$] Process specially: ftv";

    open my $fh, '>', $out;
    $fh->autoflush(1);

    my @processed_links;
    my %seen;
    my $o = Sn::FTVScraper->discover;
    for my $url (@{ $o->{links} }) {
        next if $seen{$url} || $url_seen->test($url);
        $seen{$url} = 1;

        my $article = Sn::FTVScraper->scrape($url) or next;
        if ($article->{title}) {
            my $line = encode_article_as_json($article) . "\n";
            print $fh $line;
            push @processed_links, $url;
        }
        last if @processed_links > CUTOFF;
    }
    if (@processed_links) {
        add_to_url_seen(\@processed_links);
    }

    close($fh);
}

my $url_seen;
sub add_to_url_seen {
    my ($urls) = @_;
    $url_seen->add(@$urls);
    say "Added " . (0+ @$urls) . " more urls";
}

# main

my %opts;
GetOptions(
    \%opts,
    "db|d=s"
);
die "--db <DIR> is needed" unless $opts{db} && -d $opts{db};

chdir($Bin . '/../');

$url_seen = Sn::Seen->new( store => ($opts{db} . "/url-seen.bloomfilter") );

my @initial_urls;

if (@ARGV) {
    @initial_urls = @ARGV;
} else {
    @initial_urls =  shuffle(
        @{ Sn::read_string_list('etc/news-sites.txt') },
        @{ Sn::read_string_list('etc/news-aggregation-sites.txt') },
    );
}

# jsonl => http://jsonlines.org/
if (@initial_urls) {
    MCE::Loop::init { chunk_size => 1 };
    mce_loop {
        my $url = $_;

        my $output = $opts{db} . "/articles-". Sn::ts_now() .".jsonl";
        while (-f $output) {
            sleep 1;
            $output = $opts{db} . "/articles-". Sn::ts_now() .".jsonl";
        }
        $STOP = 1 if time() - $PROCESS_START > 3000;

        if ($url =~ /ftv\.com|ftvnews\.com/) {
            process_ftv($url_seen, $output);
        } else {
            process_generic($url, $url_seen, $output);
        }
    } @initial_urls;
}

$url_seen->save;
