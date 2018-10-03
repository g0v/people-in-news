#!/usr/bin/env perl
use v5.26;
use strict;
use warnings;

use URI;
use Try::Tiny;
use MCE::Loop;
use Mojo::UserAgent;
use HTML::ExtractContent;
use Encode qw(encode_utf8 decode_utf8);
use List::Util qw(uniqstr);
use JSON::PP qw(encode_json);
use FindBin '$Bin';

sub gather_links {
    my ($url) = @_;
    my @links;

    my $ua = Mojo::UserAgent->new;
    my $res = try {
        $ua->get($url)->result;        
    } catch {
        warn "SRCERR: $url\n";
        undef;
    };
    return unless $res && $res->is_success;

    my $uri = URI->new($url);
    for my $e ($res->dom->find('a[href]')->each) {
        my $href = $e->attr("href");
        my $u = URI->new_abs("$href", $uri);
        if ($u->scheme =~ /^http/) {
            push @links, "$u";
        }
    }
    @links = uniqstr(@links);
    return @links;
}

sub extract_info {
    my ($url, $known_names) = @_;
    my %info;

    my $ua = Mojo::UserAgent->new;
    my $tx = $ua->get($url);
    my $res = $tx->result;
    return unless $res->is_success;

    my $title = $res->dom->find("title");
    return unless $title->[0];

    $info{title} = $title->[0]->text."";

    my $extractor = HTML::ExtractContent->new;
    my $html = $res->body;
    $html = decode_utf8($html) unless Encode::is_utf8($html);
    my $text = $extractor->extract($html)->as_text;
    $text =~ s/\t/ /g;
    $text =~ s/\r\n/\n/g;
    if ($text !~ m/\n\n/) {
        $text =~ s/\n/\n\n/g;
    }
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

        my $info_tsv = join(
            "\t",
            $info->{url},,
            encode_json($info->{names}),
            encode_json({

                title => $info->{title},
                content_text => $info->{content_text},
            }),
        )."\n";

        MCE->sendto("file:$out", $info_tsv);
    }
}

# main
chdir($Bin . '/../');

my @known_names = do {
    open my $fh, '<', 'etc/people.txt';
    map { chomp; $_ } <$fh>;
};

my @t = localtime();
my $timestamp = sprintf('%04d%02d%02d%02d%02d%02d', $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0]);
my $output = "out/people-news-${timestamp}.tsv";
MCE::Loop::init { chunk_size => 1, max_workers => 16 };
mce_loop_f {
    chomp;
    process($_, \@known_names, $output) if $_;
} 'etc/news-site-taiwan.txt';
