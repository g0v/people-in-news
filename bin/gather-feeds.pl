#!/usr/bin/env perl
use v5.26;
use strict;
use warnings;

use URI;
use Mojo::Promise;
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

sub extract_feed_entries {
    my ($tx) = @_;
    my $xml = $tx->res->dom;

    my @articles;
    # rss
    $xml->find("item")->each(
        sub {
            my $el = $_;
            my %o;
            for (["link", "url"], ["origLink", "url"], ["title", "title"], ["description", "content"], ["pubDate", "dateline"]) {
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

            if ($x = $el->at("updated")) {
                $o{dateline} = $x->all_text;
            } elsif($x = $el->at("published")) {
                $o{dateline} = $x->all_text;
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
    my ($urls, $cb) = @_;

    Sn::urls_get_all(
        $urls,
        sub {
            my ($tx, $url) = @_;
            my $articles = extract_feed_entries($tx);

            $cb->($articles);

            return $STOP ? 0 : 1;
        },
        sub {
            my ($error, $url) = @_;
            say STDERR "ERROR:\t$error\t$url";
            return $STOP ? 0 : 1;
        }
    );
    return;
}

sub fetch_and_extract_full_text {
    my ($articles, $cb) = @_;

    my @urls = map { $_->{url} } @$articles;
    my %u2a  = map { $_->{url} => $_ } @$articles;

    Sn::urls_get_all(
        \@urls,
        sub {
            my ($tx, $url) = @_;
            my $article = $u2a{$url};

            my $charset = Sn::tx_guess_charset($tx);
            if ($charset) {
                my $html = decode($charset, $tx->res->body);
                my $ex = Sn::HTMLExtractor->new(html => $html);
                my $text = $ex->content_text;
                if ($text && length($text) > length($article->{content_text})) {
                    # $article->{feed_content_text} = $article->{content_text};
                    $article->{content_text} = "" . $text;
                    # say "Extracted: " . encode_utf8(substr($text, 0, 40)) . "...";
                    $article->{dateline} = $ex->dateline;
                }
            }

            $article->{substrings} = Sn::extract_substrings([ $article->{title}, $article->{content_text} ]);
            $article->{t_extracted} = (0+ time());

            $cb->($article, $tx->req->url);

            return $STOP ? 0 : 1;
        },
        sub {
            my ($error, $url) = @_;
            say STDERR "ERROR: $url $error";
            return $STOP ? 0 : 1;
        }
    );

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

my @initial_urls;
if (@ARGV) {
    @initial_urls = @ARGV;
} else {
    @initial_urls = @{ Sn::read_string_list('etc/feeds.txt') };
}

my $url_seen = Sn::Seen->new( store => ($opts{db} . "/url-seen.bloomfilter") );

my $output = $opts{db} . "/articles-". Sn::ts_now() .".jsonl";
open my $fh_articles_jsonl, '>', $output;

gather_feed_links(
    \@initial_urls,
    sub {
        my $articles = $_[0];
        @$articles = grep { ! $url_seen->test($_->{url}) } @$articles;
        return unless @$articles;

        fetch_and_extract_full_text(
            $articles,
            sub {
                my ($article, $url) = @_;

                print $fh_articles_jsonl encode_json($article) . "\n";
                $url_seen->add($article->{url});
                $url_seen->add($url);
            }
        );
    }
);

$url_seen->save;
close($fh_articles_jsonl);
