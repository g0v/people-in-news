#!/usr/bin/env perl
use Sn;
use Sn::Seen;

use URI;
use Mojo::Promise;
use JSON qw(encode_json);
use Getopt::Long qw(GetOptions);
use FindBin '$Bin';
use Encode qw( decode);
use NewsExtractor;
use MCE::Loop;

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

    for my $article (@$articles) {
        last if $STOP;
        my $url = $article->{url};
        my $download = NewsExtractor->new( url => $url )->download() or next;

        my ($error, $extracted) = $download->parse;
        if ($error) {
            say STDERR "Errored at: $url\n\t" . $error->message;
        } else {
            $article->{content_text} = $extracted->article_body;
            $article->{dateline} = $extracted->dateline;
            $article->{substrings} = Sn::extract_substrings([ $article->{title}, $article->{content_text} ]);
            $article->{t_extracted} = (0+ time());

            $cb->($article, $url);
        }
    }

    return;
}

my $url_seen;
sub add_to_url_seen {
    my ($urls) = @_;
    $url_seen->add(@$urls);
    MCE->say("[$$] Seen " . (0+ @$urls) . " more urls");

    state $dirtiness = 0;
    if ($dirtiness++ > 100) {
        $url_seen->save;
        $dirtiness = 0;
    }
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

$url_seen = Sn::Seen->new( store => ($opts{db} . "/url-seen.bloomfilter") );

mce_loop {
    my ($mce, $chunk_ref, $chunk_id) = @_;

    my $id = Sn::ts_now() + $chunk_id;
    my $output = $opts{db} . "/articles-" . Sn::ts_now() . "-" . $chunk_id .".jsonl";

    open my $fh_articles_jsonl, '>', $output;

    for my $url (@{ $chunk_ref }) {
        last if $STOP;
        gather_feed_links(
            [$url],
            sub {
                my $articles = $_[0];
                @$articles = grep { ! $url_seen->test($_->{url}) } @$articles;
                return unless @$articles;

                fetch_and_extract_full_text(
                    $articles,
                    sub {
                        my ($article, $url) = @_;

                        print $fh_articles_jsonl encode_json($article) . "\n";
                        MCE->do('add_to_url_seen', [$article->{url}, $url]);
                        say "Extracted: $url";
                    }
                );
            }
        );
    }

    close $fh_articles_jsonl;
} @initial_urls;

$url_seen->save;
