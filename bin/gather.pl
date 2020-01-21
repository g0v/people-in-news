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
my $queue_urls = MCE::Queue->new();
my $queue_ftv  = MCE::Queue->new();

my $PROCESS_START = time();
my $STOP = 0;
local $SIG{INT} = sub {
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
    # $fh->autoflush(1);

    my $extracted_count = 0;

    my %seen;

    my @processed_links;

    while(my @batch = $queue_urls->dequeue(4)) {
        Sn::urls_get_all(
            \@batch,
            sub {
                my ($tx, $url) = @_;
                my ($article, $links) = Sn::ArticleExtractor->new( tx => $tx )->extract;

                if ($article) {
                    MCE->say("ARTICLE $url");

                    my $line = encode_article_as_json($article) . "\n";
                    print $fh $line;
                    push @processed_links, $url;
                }

                my $host_old = URI->new($url)->host;
                my @discovered_links = map {
                    "$_"
                } grep {
                    my $host_new = $_->host;
                    looks_like_similar_host($host_new, $host_old);
                } grep {
                    not (($_->path eq '/') or ($_->path eq ''))
                } map {
                    URI->new($_)
                } grep {
                    (not looks_like_sns_url($_))
                    and (not looks_like_xml($_))
                    and (not $url_seen->test($_))
                    and (not $seen{$_})
                } map { "$_" } @$links;

                if (@discovered_links) {
                    $queue_urls->enqueue(@discovered_links);
                    $seen{$_} = 1 for @discovered_links;
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
            MCE->say("ARTICLE $url");

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
    MCE->say( "Seen " . (0+ @$urls) . " more urls" );

    if ($dirtiness++ > 100) {
        $url_seen->save;
        $dirtiness = 0;
    }
}

sub accquire_output_filename {
    my $db_path = $_[0];
    my $t = Sn::ts_now();
    my $output = $db_path . "/articles-" . $t . ".jsonl";
    while (-f $output) {
        $t += 1;
        $output = $db_path . "/articles-" . $t . ".jsonl";
    }
    return $output;
}

## main

my %opts;
GetOptions(
    \%opts,
    "db|d=s",
    "time-limit=n",
);
die "--db <DIR> is needed" unless $opts{db} && -d $opts{db};

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
            sleep 2;
            my $pending;
            while (defined( $pending = $queue_urls->pending() ))  {
                MCE->say('[Monitor] queue_urls /pending: ' . $pending );

                if ( ($pending == 0) or (time() - $PROCESS_START > $opts{'time-limit'}) ) {
                    $queue_urls->end;
                    $queue_urls->clear;
                }

                sleep 2;
            }
        }
    }, {
        max_workers => 'auto',
        task_name => "generic",
        user_func => sub {
            my $depth = 0;
            my $output = accquire_output_filename($opts{db});
            process_generic($url_seen, $output);
            MCE->say("OUTPUT $output");
        }
    }, {
        task_name => "ftv",
        user_func => sub {
            while (my $url = $queue_ftv->dequeue_nb) {
                my $output = accquire_output_filename($opts{db});
                process_ftv($url_seen, $output);
            }
        }
    }],
);
$mce->run;
$url_seen->save();
