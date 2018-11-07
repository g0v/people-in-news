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

sub extract_feed_entries {
    my ($tx) = @_;
    my $xml = $tx->res->dom;

    my @articles;
    # rss
    $xml->find("item")->each(
        sub {
            my $el = $_;
            push @articles, {
                url   => $el->at("link")->all_text,
                title => $el->at("title")->all_text,
                content => $el->at("description")->all_text,
            };
        }
    );

    # atom
    $xml->find("entry")->each(
        sub {
            my $el = $_;
            push @articles, {
                url   => $el->at("link")->attr("href"),
                title => $el->at("title")->text,
                content => el->at("content")->all_text,
            };
        }
    );

    for(@articles) {
        my $text = Mojo::DOM->new('<body>' . (delete $_->{content}) . '</body>')->all_text();

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
        my $ua = Mojo::UserAgent->new()->max_redirects(3);
        my (@promises, @articles);

        for my $url (@$_) {
            push @promises, $ua->get_p($url)->then(
                sub {
                    my ($tx) = @_;
                    push @articles, @{ extract_feed_entries($tx) };
                }
            )->catch(
                sub {
                    my ($error) = @_;
                    say STDERR "ERROR: $url $error\n";
                }
            );

            Mojo::Promise->all(@promises)->wait() if @promises > 4;
        }
        Mojo::Promise->all(@promises)->wait() if @promises;

        MCE->gather(@articles);
    } @$urls;

    return \@articles;
}

sub fetch_and_extract_full_text {
    my ($articles) = @_;

    my @new_articles = mce_loop {
        my @articles = @$_;

        my $ua = Mojo::UserAgent->new()->max_redirects(3);
        my @promises;
        for my $article (@articles) {
            my $url = $article->{url};
            say "[$$] promise: $url";
            push @promises, $ua->get_p($url)->then(
                sub {
                    my ($tx) = @_;

                    my $charset = Sn::tx_guess_charset($tx);
                    if ($charset) {
                        my $html = decode($charset, $tx->res->body);
                        my $text = Sn::HTMLExtractor->new(html => $html)->content_text;
                        if ($text && length($text) > length($article->{content_text})) {
                            # $article->{feed_content_text} = $article->{content_text};
                            $article->{content_text} = "" . $text;
                            say "Extracted: " . encode_utf8(substr($text, 0, 40)) . "...";
                        }
                    }

                    $article->{substrings} = Sn::extract_substrings([ $article->{title}, $article->{content_text} ]);
                    $article->{t_extracted} = (0+ time());

                    MCE->gather($article);
                }
            )->catch(sub { say STDERR "ERROR: $url $_[0]" });
            Mojo::Promise->all(@promises)->wait if @promises > 4;
        }
        Mojo::Promise->all(@promises)->wait if @promises;

        MCE->gather(@articles);
    } @$articles;

    return \@new_articles;
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
    $url_seen->save;

    $articles = fetch_and_extract_full_text($articles);

    my $output = $opts{db} . "/articles-". Sn::ts_now() .".jsonl";
    open my $fh, '>', $output;
    for (@$articles) {
        print $fh encode_json($_) . "\n";
    }
    close($fh);
}
