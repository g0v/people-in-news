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

use List::Util qw(uniqstr);
use JSON::PP qw(encode_json);
use FindBin '$Bin';

sub err {
    say STDERR @_;
}

sub gather_links {
    my ($url) = @_;
    state %seen;
    $seen{$url} = 1;

    my @links;

    my $ua = Mojo::UserAgent->new;
    my $tx = try {
        $ua->get($url);
    } catch {
        err "SRCERR: $url";
        undef;
    };
    return unless $tx && $tx->res->is_success;

    $seen{$tx->req->url->to_abs . ""} = 1;

    my $uri = URI->new($url);
    for my $e ($tx->res->dom->find('a[href]')->each) {
        my $href = $e->attr("href");
        my $u = URI->new_abs("$href", $uri);
        if (!$seen{$u}  && $u->scheme =~ /^http/ && $u->host !~ /(youtube|google|facebook|twitter)\.com\z/ ) {
            $seen{"$u"} = 1;
            push @links, "$u";
        }
    }
    return @links;
}

sub extract_info {
    my ($url, $known_names) = @_;
    my %info;

    my $ua = Mojo::UserAgent->new;

    my $tx = try {
        $ua->get($url);
    } catch {
        err "FAIL TO EXTRACT: $url";
        undef;
    };
    return unless $tx;

    if($tx->error) {
        err "FAIL TO EXTRACT: $url " . encode_json($tx->error);
        return undef;
    }

    my $res = $tx->res;
    return unless $res->body;

    my $dom = $res->dom;
    my $charset;
    my $content_type = $res->headers->content_type;

    return if ( $content_type && $content_type !~ /html/);

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

    return unless $charset;

    my $title = $dom->find("title");
    return unless $title->[0];

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

    $info{content_text} = $text;

    $info{url} = $tx->req->url->to_abs;

    $info{names} = [ map { s/\t/ /g; $_ }  grep { index($title, $_) >= 0 || index($text, $_) >= 0 } @$known_names ];

    return \%info;
}

sub process {
    my ($url, $known_names, $out) = @_;
    my @links = gather_links($url);
    for my $url (@links) {
        my $info = extract_info($url, $known_names) or next;

        my $line = encode_json({
            names        => $info->{names},
            url          => "".$info->{url},
            title        => $info->{title},
            content_text => $info->{content_text},
        }) . "\n";

        MCE->sendto("file:$out", $line);
    }
}

# main
my %opts;
GetOptions(
    \%opts,
    "o=s"
);
die "-o <DIR> is needed" unless -d $opts{o};

chdir($Bin . '/../');

my @known_names = do {
    open my $fh, '<', 'etc/people.txt';
    map { chomp; decode('utf-8-strict', $_) } <$fh>;
};

my @t = localtime();
my $timestamp = sprintf('%04d%02d%02d%02d%02d%02d', $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0]);

# jsonl => http://jsonlines.org/
my $output = $opts{o} . "/people-in-news-${timestamp}.jsonl";
MCE::Loop::init { chunk_size => 1, max_workers => 16 };
mce_loop_f {
    chomp;
    process($_, \@known_names, $output) if $_;
} 'etc/news-site-taiwan.txt';
