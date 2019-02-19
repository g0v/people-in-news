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

## global
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

sub gather_links {
    my ($urls, $url_seen) = @_;

    state $ua = Mojo::UserAgent->new()->transactor(
        Mojo::UserAgent::Transactor->new()->name('Mozilla/5.0 (Macintosh; Intel Mac OS X 10.13; rv:62.0) Gecko/20100101 Firefox/62.0')
    )->max_redirects(3);

    my @promises;
    my @discovered;
    my @linkstack = (@$urls);
    my %seen = map { $_ => 1 } @linkstack;

    while (!$STOP && @linkstack) {
        my $url = pop @linkstack;
        push @promises, $ua->get_p($url)->then(
            sub {
                my ($tx) = @_;
                return unless $tx->res->is_success;
                my $uri = URI->new( "". $tx->req->url->to_abs );

                my $count = 0;
                for my $e ($tx->res->dom->find('a[href]')->each) {
                    last if $count++ > 9999;

                    my $href = $e->attr("href") or next;
                    my $u = URI->new_abs("$href", $uri);
                    $u->fragment("");
                    $u = URI->new($u->as_string =~ s/#$//r);

                    if ((! defined($seen{"$u"})) &&
                        $u->scheme =~ /^http/ &&
                        $u->host &&
                        looks_like_similar_host($u->host, $uri->host) &&
                        ($u !~ /\.(?: jpe?g|gif|png|wmv|mp[g234]|web[mp]|pdf|zip|docx?|xls|apk )\z/ix)
                    ) {
                        $seen{$u} = 1;
                        unless ($url_seen->test("$u")) {
                            push @discovered, "$u";
                        }
                    }
                }
            }
        )->catch(
            sub {
                my $err = shift;
                err "ERR: $err: $url";
            }
        );

        if (@promises > 4 || @linkstack == 0) {
            Mojo::Promise->all(@promises)->wait();
            @promises = ();
        }
    }

    if (@promises) {
        Mojo::Promise->all(@promises)->wait();
        @promises = ();
    }

    return [ uniqstr(@discovered) ];
}

sub extract_info {
    my ($tx) = @_;
    my %info;

    my $res = $tx->res;
    unless ($res->body) {
        # err "[$$] NO BODY";
        return;
    }
    $info{t_fetched} = (0+ time());

    my $charset = Sn::tx_guess_charset($tx) or return;

    my $html = decode($charset, $res->body);

    my $extractor = Sn::HTMLExtractor->new( html => $html );

    my $title = $extractor->title;
    return unless $title;

    my $text = $extractor->content_text;
    return unless $text;

    $info{title}        = "". $title;
    $info{content_text} = "". $text;
    $info{url}          = "". $tx->req->url->to_abs;
    $info{substrings}   = Sn::extract_substrings([ $title, $text ]);
    $info{t_extracted}  = (0+ time());

    say "[$$] extracted: $info{url}";
    return \%info;
}

sub process {
    my ($urls, $url_seen, $out) = @_;

    open my $fh, '>', $out;
    $fh->autoflush(1);

    my @links = @{ gather_links($urls, $url_seen) };
    if (@links) {
        say "[$$] TODO: " . (0 + @links) . " discovered links from " . join(" ", @$urls);
    }

    my @promises;
    my $error_count = 0;
    my $extracted_count = 0;
    my @processed_links;

    Sn::urls_get_all(
        \@links,
        sub {
            my ($tx, $url) = @_;
            my $info = extract_info($tx);
            push @processed_links, $url;
            if ($info) {
                my $line = encode_json($info) . "\n";
                print $fh $line;
                $extracted_count++;
            } else {
                say "[$$] Fail to extract from $url";
            }
            return $STOP ? 0 : 1;
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

MCE::Loop::init { chunk_size => 'auto', max_workers => 8 };

mce_loop {
    # jsonl => http://jsonlines.org/
    my $output = $opts{db} . "/articles-". Sn::ts_now() .".jsonl";
    while (-f $output) {
        sleep 1;
        $output = $opts{db} . "/articles-". Sn::ts_now() .".jsonl";
    }
    process($_, $url_seen, $output);
} @initial_urls;

$url_seen->save;
