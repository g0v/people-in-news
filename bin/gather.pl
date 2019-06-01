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
use JSON::PP qw(encode_json);
use FindBin '$Bin';

use Sn;
use Sn::Seen;
use Sn::Extractor;
use Sn::HTMLExtractor;
use Sn::ArticleExtractor;
use Sn::FTVScraper;

## global
my $PROCESS_START = time();
my $STOP = 0;
local $SIG{INT} = sub { $STOP = 1 };

sub err {
    say STDERR @_;
}

sub looks_like_similar_host {
    my ($host1, $host2) = @_;
    return 1 if $host1 eq $host2;
    my $rhost1 = reverse($host1);
    my $rhost2 = reverse($host2);
    return ( 0 == index($rhost2, $rhost1) );
}

sub looks_like_xml {
    my ($url) = @_;
    return $url =~ m{ \com/tag/(?:.+)\.xml \z};
}

sub process {
    my ($urls, $url_seen, $out) = @_;

    open my $fh, '>', $out;
    $fh->autoflush(1);

    my $error_count = 0;
    my $extracted_count = 0;

    my @links = @$urls;
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
                        my $line = encode_json($article) . "\n";
                        print $fh $line;
                        $extracted_count++;
                        push @processed_links, $url;
                    }
                } else {
                    say "[$$] Fail to extract from $url";
                }
                return ($STOP || ($extracted_count > 999)) ? 0 : 1;
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

    open my $fh, '>', $out;
    $fh->autoflush(1);

    my @processed_links;
    my %seen;
    my $o = Sn::FTVScraper->discover;
    for my $url (@{ $o->{links} }) {
        next if $seen{$url};
        $seen{$url} = 1;

        my $article = Sn::FTVScraper->scrape($url) or next;
        if ($article->{title}) {
            my $line = encode_json($article) . "\n";
            print $fh $line;
            push @processed_links, $url;
        }
        last if @processed_links > 999;
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
    @initial_urls = (
        @{ Sn::read_string_list('etc/news-sites.txt') },
        @{ Sn::read_string_list('etc/news-aggregation-sites.txt') },
    );
}

my @special = grep { /ftv\.com|ftvnews\.com/ } @initial_urls;
@initial_urls = grep { ! /ftv\.com|ftvnews\.com/ } @initial_urls;

# jsonl => http://jsonlines.org/

if (@special) {
    my $output = $opts{db} . "/articles-". Sn::ts_now() .".jsonl";
    while (-f $output) {
        sleep 1;
        $output = $opts{db} . "/articles-". Sn::ts_now() .".jsonl";
    }
    process_ftv($url_seen, $output);
}

if (@initial_urls) {
    MCE::Loop::init { chunk_size => 'auto' };
    mce_loop {
        my $output = $opts{db} . "/articles-". Sn::ts_now() .".jsonl";
        while (-f $output) {
            sleep 1;
            $output = $opts{db} . "/articles-". Sn::ts_now() .".jsonl";
        }
        $STOP = 1 if time() - $PROCESS_START > 3000;
        process($_, $url_seen, $output);
    } shuffle @initial_urls;
}

$url_seen->save;
