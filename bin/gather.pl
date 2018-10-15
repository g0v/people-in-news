#!/usr/bin/env perl
use v5.26;
use strict;
use warnings;

use URI;
use Try::Tiny;
use MCE::Loop;
use Mojo::UserAgent;
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

sub err {
    say STDERR @_;
}


sub gather_links {
    state %seen;
    state $ua = Mojo::UserAgent->new()->max_redirects(3);

    my ($url, $url_seen) = @_;

    my $i = 0;
    my @links = ($url);
    while ($i < @links && @links < 1000) {
        my $url = $links[$i++];
        say "+++ " . (0+ @links) . " $url";

        my $tx = try {
            $ua->get($url);
        } catch {
            err "SRCERR: $url";
            undef;
        };
        next unless $tx && $tx->res->is_success;

        $seen{$url} = $seen{$tx->req->url->to_abs . ""} = 1;

        my $uri = URI->new($url);
        for my $e ($tx->res->dom->find('a[href]')->each) {
            my $href = $e->attr("href");
            my $u = URI->new_abs("$href", $uri);
            if (!$seen{$u} && !$url_seen->test("$u") && $u->scheme =~ /^http/ && $u->host !~ /(youtube|google|facebook|twitter)/i ) {
                push @links, "$u";
            }
        }
    }

    return @links;
}

sub extract_info {
    my ($url) = @_;
    say "[$$] START $url";

    my %info;

    my $tx = try {
        my $ua = Mojo::UserAgent->new->max_redirects(3);
        $ua->get($url);
    } catch {
        err "FAIL TO FETCH: $url";
        undef;
    };
    return unless $tx;

    if ($tx->error) {
        err "FAIL TO FETCH: $url " . encode_json($tx->error);
        return undef;
    }

    my $res = $tx->res;
    unless ($res->body) {
        err "[$$] NO BODY";
        return;
    }

    my $dom = $res->dom;
    my $charset;
    my $content_type = $res->headers->content_type;

    if ( $content_type && $content_type !~ /html/) {
        err "[$$] Non HTML";
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
        err "[$$] Unknown charset";
        return;
    }

    my $title = $dom->find("title");
    unless ($title->[0]) {
        err "[$$] blank title";
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
        err "[$$] NO content";
        return;
    }

    $info{content_text} = $text;

    my @paragraphs = split /\n\n/, $text;
    my $maxl = max( map { length($_) } @paragraphs );
    if ($maxl < 60) {
        err "[$$] Not enough contents";
        return;
    }

    $info{url} = $tx->req->url->to_abs;

    return \%info;
}

sub process {
    my ($url, $url_seen, $out) = @_;

    my @links = gather_links($url, $url_seen);
    say "[$$] TODO: " . (0 + @links) . " links from $url";

    mce_loop {
        my $url = $_;

        my $info = extract_info($url) or return;

        my $line = encode_json({
            url          => "".$info->{url},
            title        => $info->{title},
            content_text => $info->{content_text},
        }) . "\n";

        MCE->sendto("file:$out", $line);
        MCE->do('add_to_url_seen', $url);
    } @links;
}

my $url_seen;
sub add_to_url_seen {
    my ($url) = @_;
    $url_seen->add($url);
}

# main
my %opts;
GetOptions(
    \%opts,
    "db|d=s"
);
die "--db <DIR> is needed" unless $opts{db} && -d $opts{db};

chdir($Bin . '/../');

# jsonl => http://jsonlines.org/
my $output = $opts{db} . "/articles-". Sn::ts_now() .".jsonl";
my $partial_output = $output . '.partial';

if (-f $output) {
    die "Output exist already: $output";
}

my $url_seen_f = $opts{db} . "/url-seen.bloomfilter";
$url_seen = Sn::Seen->new( store => $url_seen_f );

my @initial_urls;

if (@ARGV) {
    @initial_urls = @ARGV;
} else {
    open my $fh, '<', 'etc/news-site-taiwan.txt';
    @initial_urls = map { chomp; $_ } <$fh>;
    close $fh;
}

MCE::Loop::init { chunk_size => 1 };

for(shuffle(@initial_urls)) {
    process($_, $url_seen, $partial_output);
}

$url_seen->save;

rename $partial_output, $output;
