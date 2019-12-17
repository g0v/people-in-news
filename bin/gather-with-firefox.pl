#!/usr/bin/env perl
use v5.26;
use strict;
use warnings;

use URI;
use HTML::ExtractContent;
use Encode qw( decode);
use Encode::Guess;
use Getopt::Long qw(GetOptions);
use Algorithm::BloomFilter;

use List::Util qw( max);
use JSON::PP qw(encode_json);
use FindBin '$Bin';

use Sn;
use Sn::FFUA;

sub err {
    say STDERR @_;
}

sub gather_links {
    state %seen;

    my ($ua, $url, $url_seen_filter, $_level) = @_;

    my @links;

    my $tx = $ua->fetch($url) or return;

    $seen{$url} = 1;

    my $uri = URI->new($url);
    for my $e ($tx->res->dom->find('a[href]')->each) {
        my $href = $e->attr("href");
        my $u = URI->new_abs("$href", $uri);
        if (!$seen{$u}  && $u->scheme =~ /^http/ && $u->host !~ /(youtube|google|facebook|twitter)\.com\z/ ) {
            unless ($url_seen_filter->test("$u")) {
                $seen{$u} = 1;
            }
        }
    }

    return keys %seen;
}

sub extract_info {
    my ($ua, $url, $known_names) = @_;
    my %info;

    my $tx = $ua->fetch($url) or return;

    my $dom = $tx->res->dom;
    my $title = $dom->at('title')->all_text;
    return unless $title;

    $info{title} = $title;
    $info{title} =~ s/\r\n/\n/g;
    $info{title} =~ s/\A\s+//;
    $info{title} =~ s/\s+\z//;

    my $extractor = HTML::ExtractContent->new;
    my $html = $tx->res->dom . "";
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

    $info{url} = "". $url;

    $info{names} = [ map { s/\t/ /g; $_ }  grep { index($title, $_) >= 0 || index($text, $_) >= 0 } @$known_names ];

    return \%info;
}

sub process {
    my ($ua, $url, $known_names, $url_seen_filter, $out) = @_;
    open my $output_fh, '>', $out;

    my @new_links;
    my @links = gather_links($ua, $url, $url_seen_filter);
    @links = @links[0..9] if @links > 10;

    for my $url (@links) {
        my $info = extract_info($ua, $url, $known_names) or next;

        my $line = encode_json({
            names        => $info->{names},
            url          => "".$info->{url},
            title        => $info->{title},
            content_text => $info->{content_text},
        }) . "\n";

        print $output_fh $line;

        say "DONE: $url";
    }

    close($output_fh);
    return \@links;
}

# main
my %opts;
GetOptions(
    \%opts,
    "db=s"
);
die "-db <DIR> is needed" unless $opts{db} && -d $opts{db};

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

my $timestamp = Sn::ts_now();

# jsonl => http://jsonlines.org/
my $output = $opts{db} . "/articles-${timestamp}.jsonl";
my $partial_output = $output . '.partial';

if (-f $output) {
    die "Output exist already: $output";
}

my $url_seen_filter;
my $url_seen_f = $opts{db} . "/url-seen.bloomfilter";

if (-f $url_seen_f) {
    open my $fh, '<', $url_seen_f;
    my $x = do { local $/; <$fh> };
    close($fh);
    $url_seen_filter = Algorithm::BloomFilter->deserialize($x);
} else {
    $url_seen_filter = Algorithm::BloomFilter->new(50000000, 10);
}

my @new_links;
my $ua = Sn::FFUA->new;

my @inital_urls = @ARGV;
unless (@inital_urls) {
    open my $fh, '<', 'etc/news-sites.txt';
    @inital_urls = map { chomp; $_ } <$fh>;
    close($fh);
}

foreach(@inital_urls) {
    my $new_links = process($ua, $_, \@known_names, $url_seen_filter, $partial_output);
    $url_seen_filter->add(@$new_links);
}

my $x = $url_seen_filter->serialize;
open my $fh, '>', $url_seen_f;
print $fh $x;
close($fh);

rename $partial_output, $output;
