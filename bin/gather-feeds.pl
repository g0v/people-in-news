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

use Sn;
use Sn::Seen;
use Sn::Extractor;

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
        $_->{url} = "" . URI->new($_->{url});
        $_->{content_text} = Mojo::DOM->new('<body>' . $_->{content} . '</body>')->all_text();
        $_->{substrings} = Sn::extract_substrings([ $_->{title}, $_->{content_text} ]);
        $_->{t_extracted} = (0+ time());
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
    my $output = $opts{db} . "/articles-". Sn::ts_now() .".jsonl";
    open my $fh, '>', $output;
    for (@$articles) {
        print $fh encode_json($_);
    }
    close($fh);

    $url_seen->add(map { $_->{url} } @$articles);
    $url_seen->save;
}
