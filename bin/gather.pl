#!/usr/bin/env perl
use v5.26;
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

use List::Util qw(any shuffle);
use JSON ();
use FindBin '$Bin';

use Sn;
use Sn::Seen;
use Sn::Extractor;
use Sn::HTMLExtractor;
use Sn::ArticleExtractor;
use Sn::FTVScraper;

use Importer 'Sn' => qw(looks_like_similar_host);

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

sub looks_like_xml {
    my ($url) = @_;
    return $url =~ m{ \com/tag/(?:.+)\.xml \z};
}

sub process_generic {
    my ($urls, $url_seen, $out) = @_;

    open my $fh, '>', $out;
    $fh->autoflush(1);

    my $error_count = 0;
    my $extracted_count = 0;

    my @links = @$urls;
    my %seen = map { $_ => 1 } @links;

    while (!$STOP && @links) {
        my @processed_links;

        say "[$$] TODO: " . (0 + @links) . " urls";
        while(my @batch = splice(@links, 0, 4)) {
            Sn::urls_get_all(
                \@batch,
                sub {
                    my ($tx, $url) = @_;
                    my ($article, $links) = Sn::ArticleExtractor->new( tx => $tx )->extract;

                    if ($article) {
                        my $line = encode_article_as_json($article) . "\n";
                        print $fh $line;
                        push @processed_links, $url;
                    }

                    $extracted_count++;
                    $seen{$url} = 1;

                    my $host_old = URI->new($url)->host;

                    my @discovered_links = grep {
                        my $host_new = URI->new($_)->host;
                        !( $seen{$_} || $url_seen->test("$_") || looks_like_xml($_) || !looks_like_similar_host($host_new, $host_old) )
                    } @$links;

                    if (@discovered_links) {
                        MCE->do('urls_enqueue', \@discovered_links);
                    }

                    return 1;
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

            $STOP = 1 if time() - $PROCESS_START > 1200;
            last if ($STOP || ($extracted_count > CUTOFF));
        }
    }(

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
    say "Seen " . (0+ @$urls) . " more urls";
    $url_seen->save;
}

my @urls_queue;
sub urls_enqueue {
    my ($urls) = @_;
    push @urls_queue, @$urls;
    say "Queue size: " . (0+ @urls_queue) . " urls";
    return;
}

## main

my %opts;
GetOptions(
    \%opts,
    "db|d=s"
);
die "--db <DIR> is needed" unless $opts{db} && -d $opts{db};

chdir($Bin . '/../');

$url_seen = Sn::Seen->new( store => ($opts{db} . "/url-seen.bloomfilter") );

if (@ARGV) {
    @urls_queue = @ARGV;
} else {
    @urls_queue =  shuffle(
        @{ Sn::read_string_list('etc/news-sites.txt') },
        @{ Sn::read_string_list('etc/news-aggregation-sites.txt') },
    );
}

# jsonl => http://jsonlines.org/

MCE::Loop::init { chunk_size => 4000 };
while (@urls_queue) {
    mce_loop {
        my $urls = $_;
        my $output = $opts{db} . "/articles-". Sn::ts_now() .".jsonl";
        while (-f $output) {
            sleep 1;
            $output = $opts{db} . "/articles-". Sn::ts_now() .".jsonl";
        }
        $STOP = 1 if time() - $PROCESS_START > 3000;
        return if $STOP;

        if (any { /ftv\.com|ftvnews\.com/ } @$urls) {
            @$urls = grep { ! /ftv\.com|ftvnews\.com/ } @$urls;
            process_ftv($url_seen, $output);
        }
        process_generic($urls, $url_seen, $output);
    } shuffle( splice(@urls_queue) );
}

