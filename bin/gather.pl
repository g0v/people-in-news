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

sub extract_info {
    my ($tx) = @_;
    my %info;

    my $res = $tx->res;
    unless ($res->body) {
        # err "[$$] NO BODY";
        return;
    }
    $info{t_fetched} = (0+ time());
    $info{url}       = "". $tx->req->url->to_abs;

    my $charset = Sn::tx_guess_charset($tx) or return;

    my (%seen, @links);
    my $uri = URI->new( "". $tx->req->url->to_abs );
    for my $e ($tx->res->dom->find('a[href]')->each) {
        my $href = $e->attr("href") or next;
        my $u = URI->new_abs("$href", $uri);
        $u->fragment("");
        $u = URI->new($u->as_string =~ s/#$//r);
        next unless (
            $u->scheme =~ /^http/
            && $u->host
            && ($u !~ /\.(?: jpe?g|gif|png|wmv|mp[g234]|web[mp]|pdf|zip|docx?|xls|apk )\z/ix)
            && looks_like_similar_host($u->host, $uri->host)
            && (! defined($seen{"$u"}))
        );
        $seen{$u} = 1;
    }
    $info{links} = [keys %seen];

    my $html = decode($charset, $res->body);

    my $extractor = Sn::HTMLExtractor->new( html => $html );

    my $title = $extractor->title;
    return \%info unless $title;

    my $text = $extractor->content_text;
    return \%info unless $text;

    $info{title}        = "". $title;
    $info{content_text} = "". $text;
    $info{substrings}   = Sn::extract_substrings([ $title, $text ]);
    $info{t_extracted}  = (0+ time());
    $info{dateline}     = $extractor->dateline;

    unless ($info{dateline}) {
        if ($info{content_text} && $info{title}) {
            say STDERR "Faild to extract dateline: $info{url}\n";
        }
        return;
    }

    # say "[$$] extracted: $info{url}";
    return \%info;
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
        my (@discovered_links, @processed_links);

        say "[$$] TODO: " . (0 + @links) . " urls";
        Sn::urls_get_all(
            \@links,
            sub {
                my ($tx, $url) = @_;
                my $info = extract_info($tx);
                if ($info) {
                    for my $url (@{$info->{links} //[]}) {
                        unless ($seen{$url}) {
                            push @discovered_links, $url;
                            $seen{$url} = 1;
                        }
                    }
                    delete $info->{links};

                    if ($info->{title}) {
                        my $line = encode_json($info) . "\n";
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

        @links = grep { ( ! m{^https://twitter.com/intent/tweet/} ) && (! $url_seen->test("$_")) } @discovered_links;
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

MCE::Loop::init { chunk_size => 'auto' };

mce_loop {
    # jsonl => http://jsonlines.org/
    my $output = $opts{db} . "/articles-". Sn::ts_now() .".jsonl";
    while (-f $output) {
        sleep 1;
        $output = $opts{db} . "/articles-". Sn::ts_now() .".jsonl";
    }
    process($_, $url_seen, $output);
} shuffle @initial_urls;

$url_seen->save;
