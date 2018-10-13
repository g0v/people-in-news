#!/usr/bin/env perl
use v5.26;
use strict;
use warnings;

use URI;
use Try::Tiny;

use MCE::Queue;
use MCE;
use MCE::Loop;

use Mojo::UserAgent;
use HTML::ExtractContent;
use Encode qw(encode_utf8 decode);
use Encode::Guess;
use Getopt::Long qw(GetOptions);
use Algorithm::BloomFilter;

use List::Util qw(shuffle uniqstr max);
use JSON::PP qw(encode_json);
use FindBin '$Bin';

sub err {
    say STDERR @_;
}

sub ua_fetch {
    state $ua = Mojo::UserAgent->new;

    my ($url) = @_;

    my $tx = try {
        $ua->get($url);
    } catch {
        err "SRCERR: $url";
        undef;
    };
    return unless $tx && $tx->res->is_success;

    if ($tx->error) {
        err "FAIL TO FETCH: $url " . encode_json($tx->error);
        return undef;
    }

    return $tx;
}

sub harvest_links {
    state %seen;
    state $ua = Mojo::UserAgent->new;

    my ($url, $_level) = @_;
    $_level //= 0;
    return if $_level == 3;

    if ($_level > 2) {
        $seen{$url} = 1;
    }

    my @links;

    my $tx = ua_fetch($url) or return;

    $seen{$tx->req->url->to_abs . ""} = 1;

    my $uri = URI->new($url);
    for my $e ($tx->res->dom->find('a[href]')->each) {
        my $href = $e->attr("href") or next;
        my $u = URI->new_abs("$href", $uri);
        if (!$seen{$u}  && $u->scheme =~ /^http/ && $u->host !~ /(youtube|google|facebook|twitter)\.com\z/ ) {
            harvest_links("$u", $_level+1);
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

    my $tx = ua_fetch($url) or return;

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

    my @paragraphs = split /\n\n/, $text;
    return unless @paragraphs > 1;

    my $maxl = max( map { length($_) } @paragraphs );
    return if $maxl < 60;

    $info{url} = $tx->req->url->to_abs;

    # $info{names} = [ map { s/\t/ /g; $_ }  grep { index($title, $_) >= 0 || index($text, $_) >= 0 } @$known_names ];

    return \%info;
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
my @initial_links;
if (@ARGV) {
    @initial_links = @ARGV;
} else {
    open my $fh, '<', 'etc/news-site-taiwan.txt';
    @initial_links = map { chomp; $_ } <$fh>;
    close($fh);
}
@initial_links = shuffle(@initial_links);

my $queue_url = MCE::Queue->new( queue => \@initial_links );
my $queue_extract = MCE::Queue->new( fast => 1 );

my $mce = MCE->new(
   task_end => sub {
      my ($mce, $task_id, $task_name) = @_;
      $queue_extract->end() if ($task_name eq 'harvest');
   },
    user_tasks => [
        +{
            max_workers => 4,
            task_name => 'harvest',
            user_func => sub {
                while (defined (my $url = $queue_url->dequeue_nb)) {
                    say "[$$] HARVEST: $url";
                    my @links = harvest_links($url);
                    say "[$$] HARVEST: $url => " . (0+ @links) . " links";

                    $queue_extract->enqueue(@links) if @links;
                }
            }
        }, {
            task_name => 'extract',
            user_func => sub {
                while (defined (my $url = $queue_extract->dequeue)) {
                    my $info = extract_info($url);
                    my $line = encode_json({
                        names        => $info->{names},
                        url          => "".$info->{url},
                        title        => $info->{title},
                        content_text => $info->{content_text},
                    }) . "\n";

                    say "[$$] DONE: $url";
                    MCE->sendto("file:$partial_output", $line);
                    MCE->gather($url);
                }
            }
        }
    ]
)->run;

$url_seen_filter->add(@new_links);
my $x = $url_seen_filter->serialize;
open my $fh, '>', $url_seen_f;
print $fh $x;
close($fh);

rename $partial_output, $output;
