#!/usr/bin/env perl
use Sn;
use Sn::Seen;
use Sn::HTMLExtractor;

use URI;
use Mojo::UserAgent;
use Mojo::Promise;
use HTML::ExtractContent;
use Encode qw( );
use Encode::Guess;
use Getopt::Long qw(GetOptions);
use Algorithm::BloomFilter;

use List::Util qw(uniqstr shuffle);
use JSON::PP qw(encode_json);
use FindBin '$Bin';

use Log::Log4perl qw(:easy);
use WWW::Mechanize::Chrome;

use Importer 'Sn::TextUtil' => 'looks_like_similar_host';

## global
Log::Log4perl->easy_init($ERROR);
my $STOP = 0;
local $SIG{INT} = sub { $STOP = 1 };

sub err {
    say STDERR @_;
}

sub ua_fetch {
    my $url = shift;
    state $mech = WWW::Mechanize::Chrome->new();
    my ($content, $url2);
    my $err = 0;
    eval {
        $mech->get($url);
        ($content, $url2) = ($mech->content, $mech->uri);
        1;
    } or do {
        $err = $@;
        say STDERR "ua_fetch ERROR: $err";
    };
    return if $err;
    return ($content, $url2);
}

sub gather_links {
    my ($urls, $url_seen) = @_;

    my @discovered;
    my @linkstack = (@$urls);
    my %seen = map { $_ => 1 } @linkstack;

    while (!$STOP && @linkstack) {
        my $url = pop @linkstack;

        my ($content, $url2) = ua_fetch($url);
        my $uri = URI->new($url2);

        my $dom = Mojo::DOM->new($content);
        my $count = 0;
        for my $e ($dom->find('a[href]')->each) {
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
                $count++;
                $seen{$u} = 1;
                unless ($url_seen->test("$u")) {
                    push @discovered, "$u";
                }
            }

            last if $count > 999;
        }
    }

    return [ uniqstr(@discovered) ];
}

sub extract_info {
    my ($html, $url) = @_;
    return unless $html && $url;

    my %info;

    $info{url}       = "". $url;
    $info{t_fetched} = (0+ time());

    my $extractor = Sn::HTMLExtractor->new( html => $html );

    my $title = $extractor->title;
    return unless $title;

    my $text = $extractor->content_text;
    return unless $text;

    $info{title}        = "". $title;
    $info{content_text} = "". $text;
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

    my $error_count = 0;
    my $extracted_count = 0;
    my @processed_links;
    for my $url (@links) {
        last if $STOP;

        my $info = extract_info( ua_fetch($url) );
        push @processed_links, $url;
        next unless $info;

        my $line = encode_json($info) . "\n";
        print $fh $line;

        $extracted_count++;

        last if $error_count > 10;
        last if $extracted_count > 30;
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

# jsonl => http://jsonlines.org/
my $output = $opts{db} . "/articles-". Sn::ts_now() .".jsonl";
while (-f $output) {
    sleep 1;
    $output = $opts{db} . "/articles-". Sn::ts_now() .".jsonl";
}
for(shuffle @initial_urls) {
    process([$_], $url_seen, $output);
}


$url_seen->save;
