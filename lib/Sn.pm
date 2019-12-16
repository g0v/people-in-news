package Sn;
use v5.18;

use strict;
use warnings;
use Encode::Guess;
use Encode qw(encode_utf8 decode_utf8);
use List::Util qw(uniqstr);
use Mojo::Promise;
use Mojo::UserAgent;
use Time::Moment;
use HTTP::Date ();
use Try::Tiny;
use Path::Tiny qw(path);

use Sn::TX;

use constant app_root => path(__FILE__)->parent->parent;

sub promise_loop {
    my ($works, $promiser, $thener, $catcher) = @_;

    my @promises;
    for (@$works) {
        push @promises, $promiser->($_)->then($thener)->catch($catcher);
        Mojo::Promise->all(@promises)->wait() if @promises > 4;
    }
    Mojo::Promise->all(@promises)->wait() if @promises;
}

sub ua {
    state $ua = Mojo::UserAgent->new()->transactor(
        Mojo::UserAgent::Transactor->new()->name('Mozilla/5.0 (Macintosh; Intel Mac OS X 10.13; rv:67.0) Gecko/20100101 Firefox/67.0')
    )->max_redirects(3);
    return $ua;
}

sub urls_get_all {
    my ($urls, $on_success_cb, $on_error_cb) = @_;

    my $ua = ua();
    my @promises;
    my $should_stop = 0;
    for my $url (@$urls) {
        last if $should_stop;

        push @promises, $ua->get_p($url)->then(
            sub {
                my ($tx) = @_;
                unless ($tx->res->is_success) {
                    say 'NOT SUCCESSFUL: ' . $tx->res->code . ': '. $url;
                    return;
                }

                unless ($on_success_cb->($tx, $url)) {
                    $should_stop = 1;
                }
            }
        )->catch(
            sub {
                unless ($on_error_cb->($_[0], $url)) {
                    $should_stop = 1;
                }
            }
        );

        if (@promises > 2) {
            Mojo::Promise->all(@promises)->wait;
            @promises = ();
        }
    }

    if (@promises) {
        Mojo::Promise->all(@promises)->wait();
        @promises = ();
    }
}

sub ts_now {
    my @t = localtime();
    return sprintf('%04d%02d%02d%02d%02d%02d', $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0]);
}

sub yyyymmdd_now {
    my @t = localtime();
    return sprintf('%04d%02d%02d', $t[5]+1900, $t[4]+1, $t[3]);
}

sub trim_whitespace {
    local $_ = $_[0];
    s/\r//g;
    s/\t/ /g;
    s/ +\n/\n/g;
    s/\n +/\n/g;
    s/\A\s+//;
    s/\s+\Z//;
    return $_;
}

sub readlines {
    my ($fn) = @_;

    open my $fh, '<', $fn;
    my @lines = map { chomp; $_ } <$fh>;
    close($fh);

    return \@lines;
}

sub readlines_utf8 {
    my ($fn) = @_;

    open my $fh, '<', $fn;
    my @lines = map { chomp; decode_utf8($_); } <$fh>;
    close($fh);

    return \@lines;
}

sub read_string_list {
    my ($fn) = @_;
    my @lines = grep {
        s/\A#.+\z//;
        s/\A\s+//;
        s/\s+\z//;

        $_ ne ''
    } @{ readlines_utf8($fn) };

    return \@lines;
}

sub load_substr_file {
    my ($fn) = @_;
    my @token = uniqstr map { split /\t+/ } @{ read_string_list($fn) };
    return \@token;
}

sub load_tokens {
    my %token;
    for my $fn ( sort { $a cmp $b } app_root->child('etc')->children(qr{substr-.+\.txt\z}) ) {
        my ($token_type) = $fn =~ m{substr-(.+)\.txt$};
        my @tokens = uniqstr map { split /\t+/ } @{ read_string_list($fn) };
        for (@tokens) {
            push @{$token{$_}}, $token_type;
        }
    }
    return \%token;
}

sub extract_substrings {
    my ($texts) = @_;

    state (%token, @tokens);
    unless (%token) {
        %token = %{ load_tokens() };
        @tokens = sort { length($b) <=> length($a) } keys %token;
    }

    my %extracts;
    for my $text (@$texts) {
        my (%matched, %cov);
        for my $tok (@tokens) {
            my $pos = index($text, $tok, 0);
            if ($pos >= 0) {
                unless ( $cov{$pos} && $cov{$pos + length($tok)} ) {
                    $matched{$tok} = $pos;
                    $cov{$_}++ for $pos ... $pos+length($tok);
                }
            }
        }

        for my $tok (keys %matched) {
            for my $token_type (@{$token{$tok}}) {
                push @{ $extracts{ $token_type } }, $tok;
            }
        }
    }

    for my $t (keys %extracts) {
        @{$extracts{$t}} = uniqstr @{$extracts{$t}};
    }

    return \%extracts;
}

sub tx_guess_charset {
    my ($tx) = @_;
    my $charset;
    my $content_type = $tx->res->headers->content_type;

    if ( $content_type && $content_type !~ /html/) {
        # err "[$$] Non HTML";
        return;
    }

    if ( $content_type && $content_type =~ m!charset=(.+)[;\s]?!) {
        $charset = $1;
    }

    my $dom;
    if (!$charset) {
        $dom = $tx->res->dom;
        if (my $meta_el = $dom->at("meta[http-equiv=Content-Type]")) {
            ($charset) = $meta_el->attr('content') =~ m{charset=([^\s;]+)};
            $charset = lc($charset) if defined($charset);
        }
    }
    $charset = 'utf-8-strict' if $charset && $charset =~ /utf-?8/i;

    my $resbody = $tx->res->body;
    if (!$charset) {
        if (!defined($resbody) || $resbody eq '') {
            return;
        }

        my $enc = guess_encoding($resbody, qw/big5 utf8/);
        $charset = $enc->name if $enc;
    }

    unless ($charset) {
        # err "[$$] Unknown charset";
        return;
    }

    return $charset;
}

sub parse_dateline {
    my ($dateline) = @_;
    my $tm = try { Time::Moment->from_string($dateline, lenient => 1) };
    if (!$tm) {
        if (my $ts = HTTP::Date::str2time($dateline, '+0800')) {
            $tm = try {
                Time::Moment->from_epoch($ts);
            }
        }
    }

    return $tm;
}

sub print_full_article {
    my ($fh, $article) = @_;
    my $out = "";

    $out .= "# BEGIN ARTICLE\n";
    $out .= "Title: $article->{title}\n";
    $out .= "Dateline: " . ($article->{dateline} // "") . "\n";
    $out .= "Journalist: " . ($article->{journalist} // "") . "\n";
    $out .= "URL: $article->{url}\n";
    for my $type (keys %{$article->{substrings}}) {
        my @tokens = @{$article->{substrings}{$type}} or next;
        $out .= "Token-${type}: " . join(" ", @tokens) . "\n";
    }
    $out .= "\n$article->{content_text}\n\n";

    $out .= "# END ARTICLE\n";

    say $fh encode_utf8($out);
}

1;
