#!/usr/bin/env perl
use v5.26;
use strict;
use warnings;

use URI;
use MCE::Loop;
use Mojo::UserAgent;
use JSON qw(encode_json);
use Getopt::Long qw(GetOptions);
use FindBin '$Bin';
use Encode qw(encode_utf8 decode);

use Sn;
use Sn::Seen;
use Sn::Extractor;
use Sn::HTMLExtractor;

## global
my $STOP = 0;
local $SIG{INT} = sub { $STOP = 1 };
MCE::Loop::init { max_workers => 4 };

sub extract_feed_entries {
    my ($tx) = @_;
    my $xml = $tx->res->dom;

    my @articles;
    # rss
    $xml->find("item")->each(
        sub {
            my $el = $_;
            my %o;
            for (["link", "url"], ["title", "title"], ["description", "content"]) {
                my $x = $el->at($_->[0]) or next;
                $o{ $_->[1] } = $x->all_text;
            }
            push @articles, \%o if $o{url};
        }
    );

    # atom
    $xml->find("entry")->each(
        sub {
            my $el = $_;
            my (%o, $x);

            if ($x = $el->at("link")) {
                $o{url} = $x->attr("href");
            }
            if ($x = $el->at("title")) {
                $o{title} = $x->text;
            }
            if ($x = $el->at("content")) {
                $o{content} = $x->all_text;
            }

            push @articles, \%o if $o{url};
        }
    );

    for(@articles) {
        my $text = Mojo::DOM->new('<body>' . ((delete $_->{content}) // '') . '</body>')->all_text();

        $_->{content_text} = Sn::trim_whitespace($text);
        $_->{title} = Sn::trim_whitespace($_->{title});
        $_->{content_text} = "". $text;
        $_->{url} = "" . URI->new($_->{url});
    }

    return \@articles;
}

sub gather_feed_links {
    my ($urls) = @_;

    my @articles = mce_loop {
        my $urls = $_;
        my $ua = Mojo::UserAgent->new()->max_redirects(3);

        my @articles;

        Sn::urls_get_all(
            $urls,
            sub {
                my ($tx, $url) = @_;
                push @articles, @{ extract_feed_entries($tx) };
                return $STOP ? 0 : 1;
            },
            sub {
                my ($error, $url) = @_;
                say STDERR "ERROR:\t$error\t$url";
                return $STOP ? 0 : 1;
            }
        );

        MCE->gather(@articles);
    } @$urls;

    return \@articles;
}

sub fetch_and_extract_full_text {
    my ($articles) = @_;

    my @o = mce_loop {
        my @articles = @$_;
        my @urls = map { $_->{url} } @articles;
        my %u2a  = map { $_->{url} => $_ } @articles;

        Sn::urls_get_all(
            \@urls,
            sub {
                my ($tx, $url) = @_;
                my $article = $u2a{$url};

                my $charset = Sn::tx_guess_charset($tx);
                if ($charset) {
                    my $html = decode($charset, $tx->res->body);
                    my $text = Sn::HTMLExtractor->new(html => $html)->content_text;
                    if ($text && length($text) > length($article->{content_text})) {
                        # $article->{feed_content_text} = $article->{content_text};
                        $article->{content_text} = "" . $text;
                        # say "Extracted: " . encode_utf8(substr($text, 0, 40)) . "...";
                    }
                }

                $article->{substrings} = Sn::extract_substrings([ $article->{title}, $article->{content_text} ]);
                $article->{t_extracted} = (0+ time());

                MCE->gather([ $article, $tx->req->url ]);
                return 1;
            },
            sub {
                my ($error, $url) = @_;
                say STDERR "ERROR: $url $error";
                return 1;
            }
        );
    } @$articles;

    my @new_articles = map { $_->[0] } @o;
    my @new_urls = map { $_->[1] } @o;
    return \@new_articles, \@new_urls;
}

## main
my %opts;
GetOptions(
    \%opts,
    "db|d=s"
);
die "--db <DIR> is needed" unless $opts{db} && -d $opts{db};
chdir($Bin . '/../');

my @initial_urls;
if (@ARGV) {
    @initial_urls = @ARGV;
} else {
    @initial_urls = @{ Sn::read_string_list('etc/feeds.txt') };
}

my $url_seen = Sn::Seen->new( store => ($opts{db} . "/url-seen.bloomfilter") );

my $articles = gather_feed_links(\@initial_urls);

@$articles = grep { ! $url_seen->test($_->{url}) } @$articles;

if (@$articles) {
    $url_seen->add(map { $_->{url} } @$articles);
    ($articles, my $new_urls) = fetch_and_extract_full_text($articles);

    $url_seen->add(@$new_urls);
    $url_seen->save;

    my $output = $opts{db} . "/articles-". Sn::ts_now() .".jsonl";
    open my $fh, '>', $output;
    for (@$articles) {
        print $fh encode_json($_) . "\n";
    }
    close($fh);
}
