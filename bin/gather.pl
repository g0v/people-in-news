#!/usr/bin/env perl
use v5.26;
use warnings;

use URI;
use MCE;
use MCE::Queue;
use Getopt::Long qw(GetOptions);

use List::Util qw( shuffle);
use JSON ();
use FindBin '$Bin';

use Sn;
use Sn::Seen;
use Sn::ArticleExtractor;
use Sn::FTVScraper;

use Importer 'Sn::TextUtil' => qw(looks_like_similar_host looks_like_sns_url);

## global
my %is_initial_url;
my $queue_unique_urls = MCE::Queue->new();
my $queue_urls = MCE::Queue->new();
my $queue_ftv  = MCE::Queue->new();

my $PROCESS_START = time();
my $STOP = 0;
local $SIG{INT} = sub {
    $queue_unique_urls->clear;
    $queue_unique_urls->end;
    $queue_urls->clear;
    $queue_urls->end;

    $STOP = 1;
};

sub encode_article_as_json {
    state $json = JSON->new->utf8->canonical;
    $json->encode($_[0]);
}

sub looks_like_xml {
    my ($url) = @_;
    return $url =~ m{ \com/tag/(?:.+)\.xml \z};
}

sub process_generic {
    my ($url_seen, $out) = @_;

    open my $fh, '>', $out;

    my $extracted_count = 0;

    my @processed_links;

    while(my @batch = $queue_unique_urls->dequeue(1)) {
        Sn::urls_get_all(
            \@batch,
            sub {
                my ($tx, $url) = @_;
                my ($article, $links) = Sn::ArticleExtractor->new( tx => $tx )->extract;

                my $host_old = URI->new($url)->host;
                my @discovered_links = grep {
                    my $u = "$_";
                    my $uri = URI->new($u);

                    (not looks_like_sns_url($u))
                    and (not looks_like_xml($u))
                    and (not $url_seen->test($u))
                    and (not (($uri->path eq '/') or ($uri->path eq '')))
                    and looks_like_similar_host($uri->host, $host_old)
                } @$links;

                if ($article and (! $is_initial_url{$url})) {
                    MCE->say("[generic] ARTICLE $url");

                    my $line = encode_article_as_json($article) . "\n";
                    print $fh $line;
                    push @processed_links, $url;
                } else {
                    MCE->say("[generic] NOARTICLE $url, discovered_links=" . (0+ @discovered_links));
                }

                if (@discovered_links) {
                    $queue_urls->enqueue(@discovered_links);
                }

                return 1;
            },
            sub {
                my ($error, $url) = @_;
                MCE->say("ERROR:\t$error\t$url");
                return $STOP ? 0 : 1;
            }
        );

        last if $STOP;
    }

    close($fh);

    if (@processed_links) {
        MCE->do('add_to_url_seen', \@processed_links);
    }

    return;
}

sub process_ftv {
    my ($url_seen, $out) = @_;

    MCE->say("[$$] Process specially: ftv");

    open my $fh, '>', $out;
    $fh->autoflush(1);

    my @processed_links;
    my %seen;
    my $o = Sn::FTVScraper->discover;
    for my $url (@{ $o->{links} }) {
        next if $seen{$url} || $url_seen->test($url);
        $seen{$url} = 1;

        my $article = Sn::FTVScraper->scrape($url) or next;
        if ($article->{title}) {
            MCE->say("[ftv] ARTICLE $url");

            my $line = encode_article_as_json($article) . "\n";
            print $fh $line;
            push @processed_links, $url;
        }
    }
    if (@processed_links) {
        MCE->do('add_to_url_seen', \@processed_links);
    }

    close($fh);
}

my $dirtiness = 0;
my $url_seen;
sub add_to_url_seen {
    my ($urls) = @_;
    $url_seen->add(@$urls);
    MCE->say("[$$] Seen " . (0+ @$urls) . " more urls");

    if ($dirtiness++ > 100) {
        $url_seen->save;
        $dirtiness = 0;
    }
}

## main

my %opts;
GetOptions(
    \%opts,
    "db|d=s",
    "time-limit=n",
);
die "--db <DIR> is needed" unless $opts{db} && -d $opts{db};

$opts{db} =~ s{/$}{};
$opts{'time-limit'} //= 1200;

chdir($Bin . '/../');

$url_seen = Sn::Seen->new( store => ($opts{db} . "/url-seen.bloomfilter") );

my @initial_urls;
if (@ARGV) {
    @initial_urls = @ARGV;
} else {
    @initial_urls = shuffle(
        @{ Sn::read_string_list('etc/news-sites.txt') },
    );
}

for my $it (@initial_urls) {
    $is_initial_url{$it} = 1;
    if ( $it =~ m/ftv/ ) {
        $queue_ftv->enqueue($it);
    } else {
        $queue_urls->enqueue($it)
    }
}

my $mce = MCE->new(
    user_tasks => [{
        task_name => "supervisor",
        user_func => sub {
            sleep 60;
            my $pending;
            while (defined( $pending = $queue_unique_urls->pending() ))  {
                my $duration = time() - $PROCESS_START;

                MCE->say("[Monitor] duration=${duration}, pending=${pending}");

                if ( ($pending == 0) or ($duration > $opts{'time-limit'}) ) {
                    $queue_unique_urls->clear;
                    $queue_unique_urls->end;
                    $queue_urls->clear;
                    $queue_urls->end;
                }

                sleep 10;
            }
        }
    }, {
        max_workers => '1',
        task_name => "deduper",
        user_func => sub {
            my %seen;
            while(my $url = $queue_urls->dequeue()) {
                unless ($seen{$url}) {
                    $queue_unique_urls->enqueue($url);
                    $seen{$url} = 1;
                }
            }
        }
    }, {
        max_workers => 'auto',
        task_name => "generic",
        user_func => sub {
            my ($mce) = @_;
            my $wid = $mce->wid;
            my $ts  = Sn::ts_now();
            my $output = $opts{db} . "/articles-${ts}-${wid}.jsonl";
            process_generic($url_seen, $output);
            MCE->say("OUTPUT $output");
        }
    }, {
        task_name => "ftv",
        user_func => sub {
            while (my $url = $queue_ftv->dequeue_nb) {
                my ($mce) = @_;
                my $wid = $mce->wid;
                my $ts  = Sn::ts_now();
                my $output = $opts{db} . "/articles-${ts}-${wid}.jsonl";
                process_ftv($url_seen, $output);
                MCE->say("OUTPUT $output");
            }
        }
    }],
);
$mce->run;
$url_seen->save();
