#!/usr/bin/env perl
use v5.26;
use strict;
use warnings;

use URI;
use Try::Tiny;
use MCE::Loop;
use HTML::ExtractContent;
use Encode qw(encode_utf8 decode);
use Encode::Guess;
use Getopt::Long qw(GetOptions);
use Algorithm::BloomFilter;

use List::Util qw(uniqstr max);
use JSON::PP qw(encode_json);
use FindBin '$Bin';

use Sn;

sub err {
    say STDERR @_;
}

sub gather_links {
    state %seen;

    my ($url, $url_seen_filter, $_level) = @_;
    $_level //= 0;
    return if $_level == 3 || ( (keys %seen) > 100);

    if ($_level > 2) {
        $seen{$url} = 1;
    }

    my @links;

    my $tx = Sn::fetch($url) or return;
    return if $tx->no_content;

    $seen{$tx->uri} = 1;

    my $uri = URI->new($url);
    for my $e ($tx->dom->find('a[href]')->each) {
        my $href = $e->attr("href");
        my $u = URI->new_abs("$href", $uri);
        if (!$seen{$u}  && $u->scheme =~ /^http/ && $u->host !~ /(youtube|google|facebook|twitter)\.com\z/ ) {
            $seen{$u} = 1;
            # unless ($url_seen_filter->test("$u")) {
            #     gather_links("$u", $url_seen_filter, $_level+1);
            # }
        }
    }
    if ($_level == 0) {
        return keys %seen;
    }
    return;
}

sub extract_info {
    my ($url, $known_names) = @_;
    my %info;

    my $tx = Sn::fetch($url) or return;
    return if $tx->no_content;

    my $dom = $tx->dom;
    my $title = $tx->title;
    return unless $title;

    $info{title} = $title;
    $info{title} =~ s/\r\n/\n/g;
    $info{title} =~ s/\A\s+//;
    $info{title} =~ s/\s+\z//;

    my $extractor = HTML::ExtractContent->new;
    my $html = $tx->dom . "";
    my $text = $extractor->extract($html)->as_text;
    $text =~ s/\t/ /g;
    $text =~ s/\r\n/\n/g;
    if ($text !~ m/\n\n/) {
        $text =~ s/\n/\n\n/g;
    }
    $text =~ s/\A\s+//;
    $text =~ s/\s+\z//;

    $info{content_text} = $text;

    my @paragraphs = split /\n\n/, $text;
    return unless @paragraphs > 1;

    my $maxl = max( map { length($_) } @paragraphs );
    return if $maxl < 60;

    $info{url} = "". $tx->uri;

    $info{names} = [ map { s/\t/ /g; $_ }  grep { index($title, $_) >= 0 || index($text, $_) >= 0 } @$known_names ];

    return \%info;
}

sub process {
    my ($url, $known_names, $url_seen_filter, $out) = @_;

    my @links = gather_links($url, $url_seen_filter);
    say 'TODO: ' . (0 + @links) . ' links from ' . $url;
    for my $url (@links) {
        my $info = extract_info($url, $known_names) or next;

        my $line = encode_json({
            names        => $info->{names},
            url          => "".$info->{url},
            title        => $info->{title},
            content_text => $info->{content_text},
        }) . "\n";

        say "DONE: $url";
        MCE->sendto("file:$out", $line);
        MCE->gather($url);
    }
}

# main
my %opts;
GetOptions(
    \%opts,
    "o=s"
);
die "-o <DIR> is needed" unless $opts{o} && -d $opts{o};

chdir($Bin . '/../');

my @known_names = do {
    my @people_input = glob('etc/people*.txt');
    my @ret;
    for my $fn (@people_input) {
        open my $fh, '<', $fn;
        push @ret, map { chomp; decode('utf-8-strict', $_) } <$fh>;        
    }
    @ret;
};

my @t = localtime();
my $hourstamp = sprintf('%04d%02d%02d%02d%02d%02d', $t[5]+1900, $t[4]+1, $t[3], $t[2], 0, 0);

# jsonl => http://jsonlines.org/
my $output = $opts{o} . "/people-in-news-${hourstamp}.jsonl";
my $partial_output = $output . '.partial';

if (-f $output) {
    die "Output exist already: $output";
}

my $url_seen_filter;
my $url_seen_f = $opts{o} . "/people-in-news-url-seen.bloomfilter";

if (-f $url_seen_f) {
    open my $fh, '<', $url_seen_f;
    my $x = do { local $/; <$fh> };
    close($fh);
    $url_seen_filter = Algorithm::BloomFilter->deserialize($x);
} else {
    $url_seen_filter = Algorithm::BloomFilter->new(50000000, 10);
}

my @new_links;
MCE::Loop::init { chunk_size => 1, max_workers => 1 };
if (@ARGV) {
    @new_links = mce_loop {
        process($_, \@known_names, $url_seen_filter, $partial_output);
    } @ARGV;
} else {
    @new_links = mce_loop_f {
        chomp;
        process($_, \@known_names, $url_seen_filter, $partial_output) if $_;
    } 'etc/news-site-taiwan.txt';
}

$url_seen_filter->add(@new_links);
my $x = $url_seen_filter->serialize;
open my $fh, '>', $url_seen_f;
print $fh $x;
close($fh);

rename $partial_output, $output;