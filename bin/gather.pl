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

    state $ua = Mojo::UserAgent->new()->max_redirects(3);

    my @promises;
    my $iters = 0;
    my @discovered;
    my @linkstack = (@$urls);
    my @linkstack2;
    my %depth = map { $_ => 1 } @linkstack;

    while (!$STOP && @linkstack && @discovered < 10000 && $iters++ < 100) {
        my $url = pop @linkstack;
        next if $depth{$url} > 2;

        say ">>> ($iters) <" . (0+ @linkstack) . ", " . (0+ @discovered). "> $url";
        push @promises, $ua->get_p($url)->then(
            sub {
                my ($tx) = @_;
                return unless $tx->res->is_success;
                my $uri = URI->new( "". $tx->req->url->to_abs );

                my @new_links;
                for my $e ($tx->res->dom->find('a[href]')->each) {
                    my $href = $e->attr("href") or next;
                    my $u = URI->new_abs("$href", $uri);
                    $u->fragment("");
                    $u = URI->new($u->as_string =~ s/#$//r);

                    if ((! defined($depth{"$u"})) &&
                        $u->scheme =~ /^http/ &&
                        $u->host &&
                        looks_like_similar_host($u->host, $uri->host) &&
                        ($u !~ /\.(?: jpe?g|gif|png|wmv|mp[g234]|web[mp]|pdf|zip|docx?|xls|apk )\z/ix)
                    ) {
                        $depth{$u} = $depth{$url} + 1;
                        push @linkstack2, "$u";
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

        if (!@linkstack && @linkstack2) {
            @linkstack = shuffle(uniqstr(@linkstack2));
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
    # say "[$$] START $url";

    my %info;

    my $res = $tx->res;
    unless ($res->body) {
        # err "[$$] NO BODY";
        return;
    }

    $info{t_fetched} = (0+ time());

    my $dom = $res->dom;
    my $charset;
    my $content_type = $res->headers->content_type;

    if ( $content_type && $content_type !~ /html/) {
        # err "[$$] Non HTML";
        return;
    }

    if ( $content_type && $content_type =~ m!charset=(.+)[;\s]?!) {
        $charset = $1;
    }

    if (!$charset) {
        if (my $meta_el = $dom->find("meta[http-equiv=Content-Type]")->first) {
            ($charset) = $meta_el->{content} =~ m{charset=([^\s;]+)};
            $charset = lc($charset) if defined($charset);
        }
    }
    $charset = 'utf-8-strict' if $charset && $charset =~ /utf-?8/i;

    if (!$charset) {
        my $enc = guess_encoding($res->body, qw/big5 utf8/);
        $charset = $enc->name if $enc;
    }

    unless ($charset) {
        # err "[$$] Unknown charset";
        return;
    }

    my $title = $dom->find("title");
    unless ($title->[0]) {
        # err "[$$] blank title";
        return;
    }

    $info{title} = $title->[0]->text."";
    $info{title} = decode($charset, $info{title}) unless Encode::is_utf8($info{title});
    $info{title} =~ s/\r\n/\n/g;
    $info{title} =~ s/\A\s+//;
    $info{title} =~ s/\s+\z//;

    my $extractor = HTML::ExtractContent->new;
    my $html = decode($charset, $res->body);

    my $text = $extractor->extract($html)->as_text;
    $text =~ s/\t/ /g;
    $text =~ s/\r\n/\n/g;
    if ($text !~ m/\n\n/) {
        $text =~ s/\n/\n\n/g;
    }
    $text =~ s/\A\s+//;
    $text =~ s/\s+\z//;

    unless ($text) {
        # err "[$$] NO content";
        return;
    }

    my @paragraphs = split /\n\n/, $text;
    my $maxl = max( map { length($_) } @paragraphs );
    if ($maxl < 60) {
        # err "[$$] Not enough contents";
        return;
    }

    $info{url}          = "". $tx->req->url->to_abs;
    $info{content_text} = $text;
    $info{substrings}   = Sn::extract_substrings([ $info{title}, $text ]);
    $info{t_extracted}  = (0+ time());

    return \%info;
}

sub process {
    state $ua = Mojo::UserAgent->new()->transactor(
        Mojo::UserAgent::Transactor->new()->name('Mozilla/5.0 (Macintosh; Intel Mac OS X 10.13; rv:62.0) Gecko/20100101 Firefox/62.0')
    )->max_redirects(3);

    my ($urls, $url_seen, $out) = @_;

    open my $fh, '>', $out;
    $fh->autoflush(1);

    my @links = @{ gather_links($urls, $url_seen) };
    say "[$$] TODO: " . (0 + @links) . " discovered links from " . join(" ", @$urls);

    my @promises;
    my $error_count = 0;
    my $extracted_count = 0;
    for my $url (@links) {
        if ($url =~ /\.(?: jpe?g|gif|png|wmv|mp[g234]|web[mp]|pdf|zip|docx?|xls|apk )\z/ix) {
            err "[$$] Non-HTML-ish: $url";
            next;
        }

        push @promises, $ua->get_p($url)->then(
            sub {
                my ($tx) = @_;
                return unless $tx->res->is_success;
                my $info = extract_info($tx) or return;
                my $line = encode_json($info) . "\n";
                print $fh $line;
                $extracted_count++;
            }
        )->catch(
            sub {
                $error_count++
            }
        );

        if (@promises > 3) {
            Mojo::Promise->all(@promises)->wait;
            @promises = ();
        }

        last if $error_count > 10;
        last if $extracted_count > 30;
    }

    if (@promises) {
        Mojo::Promise->all(@promises)->wait();
        @promises = ();
    }

    if (@links) {
        MCE->do('add_to_url_seen', \@links);
    } else {
        unlink($out);
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
    @initial_urls = @{ Sn::read_string_list('etc/news-sites.txt') };
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

} @initial_urls;

$url_seen->save;
