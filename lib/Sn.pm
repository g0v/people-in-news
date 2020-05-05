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
    state @promises;

    my $ua = ua();
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

sub current_year {
    my @t = localtime();
    return $t[5]+1900;
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

sub print_article_like_mail {
    my ($fh, $article) = @_;
    my $out = "";

     my ($sec,$min,$hour,$mday,$_mon,$year,$_wday,$yday,undef) = localtime(time);
    my @mon = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
    my @wday = qw(Sun Mon Tue Wed Thu Fri Sat);
    $year+= 1900;

    $out .= "From nobody $wday[$_wday] $mon[$_mon] $mday $hour:$min:$sec $year\n";
    $out .= "From: " . ($article->{journalist} // "unknown") . "\n";
    $out .= "Subject: $article->{title}\n";
    $out .= "Content-Type: text/plain; charset=utf8\n";
    $out .= "X-Dateline: " . ($article->{dateline} // "") . "\n";
    $out .= "X-URL: $article->{url}\n";
    for my $type (keys %{$article->{substrings}}) {
        my @tokens = @{$article->{substrings}{$type}} or next;
        $out .= "X-Token-${type}: " . join(" ", uniqstr(@tokens)) . "\n";
    }
    $out .= "\n$article->{content_text}\n\n";

    say $fh encode_utf8($out);
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
        $out .= "Token-${type}: " . join(" ", uniqstr(@tokens)) . "\n";
    }
    $out .= "\n$article->{content_text}\n\n";

    $out .= "# END ARTICLE\n";

    say $fh encode_utf8($out);
}

1;
