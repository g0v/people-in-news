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
use Sn::KnownNames;

sub err {
    say STDERR @_;
}

sub ua_get {
    state $ua = Mojo::UserAgent->new()->transactor(
        Mojo::UserAgent::Transactor->new()->name('Mozilla/5.0 (Macintosh; Intel Mac OS X 10.13; rv:62.0) Gecko/20100101 Firefox/62.0')
    )->max_redirects(3);

    my ($url) = @_;
    return $ua->get_p($url);
}

sub gather_links {
    my ($url) = @_;

    my @promises;
    my $error_count = 0;
    my $i = 0;
    my @links = ($url);
    my %seen  = ($url => 1);

    while (@links < 1000 && $error_count < 10) {
        if (@promises > 30 || (($i >= @links) && @promises)) {
            Mojo::Promise->all(@promises)->wait();
            @promises = ();
        }

        last if $i >= @links;
        my $url = $links[$i++];

        push @promises, ua_get($url)->then(
            sub {
                my ($tx) = @_;
                return unless $tx->res->is_success;
                my $url2 = $tx->req->url->to_abs . "";
                $seen{$url} = $seen{$url2} = 1;

                my $uri = URI->new($url2);
                for my $e ($tx->res->dom->find('a[href]')->each) {
                    my $href = $e->attr("href");
                    my $u = URI->new_abs("$href", $uri);
                    if (!$seen{$u} && $u->scheme =~ /^http/ && $u->host && $u->host eq $uri->host) {
                        push @links, "$u";
                        $seen{$u} = 1;
                    }
                }
            }
        )->catch(
            sub {
                my $err = shift;
                err "ERR: $err @_";
                $error_count++;
            }
        );
    }

    if (@promises) {
        Mojo::Promise->all(@promises)->wait();
        @promises = ();
    }

    return uniqstr(@links);
}

sub extract_names {
    my ($texts) = @_;
    state $kn = Sn::KnownNames->new( input => [  glob('etc/substr-*.txt') ] );

    my @extracted;
    for my $name (@{$kn->known_names}) {
        for my $txt (@$texts) {
            if (index($txt, $name) >= 0) {
                push @extracted, $name;
                last;
            }
        }
    }
    return \@extracted;
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

    $info{names}        = extract_names([ $info{title}, $text ]);
    $info{url}          = "". $tx->req->url->to_abs;
    $info{content_text} = $text;
    $info{t_extracted}  = (0+ time());

    return \%info;
}

sub process {
    my ($url, $url_seen, $out) = @_;

    open my $fh, '>', $out;
    $fh->autoflush(1);

    my @links = grep { ! $url_seen->test($_) } gather_links($url);
    say "[$$] TODO: " . (0 + @links) . " links from $url";

    my @promises;
    my $error_count = 0;
    my $extracted_count = 0;
    for my $url (@links) {
        if ($url =~ /\.(?: jpe?g|gif|png|wmv|mp[g234]|web[mp]|pdf )\z/ix) {
            # err "[$$] Does not look like HTML-ish";
            next;
        }

        push @promises, ua_get($url)->then(
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
    open my $fh, '<', 'etc/news-site-taiwan.txt';
    @initial_urls = map { chomp; $_ } <$fh>;
    close $fh;
}

MCE::Loop::init { chunk_size => 'auto' };

mce_loop {
    for(@$_) {
        # jsonl => http://jsonlines.org/
        my $output = $opts{db} . "/articles-". Sn::ts_now() .".jsonl";
        while (-f $output) {
            sleep 1;
            $output = $opts{db} . "/articles-". Sn::ts_now() .".jsonl";
        }

        process($_, $url_seen, $output);
    }
} @initial_urls;

$url_seen->save;
