package Sn;
use v5.18;

use strict;
use warnings;
use Encode::Guess;
use Encode qw(decode_utf8);
use List::Util qw(uniqstr);
use Mojo::Promise;

use Sn::TX;

sub promise_loop {
    my ($works, $promiser, $thener, $catcher) = @_;

    my @promises;
    for (@$works) {
        push @promises, $promiser->($_)->then($thener)->catch($catcher);
        Mojo::Promise->all(@promises)->wait() if @promises > 4;
    }
    Mojo::Promise->all(@promises)->wait() if @promises;
}


sub ts_now {
    my @t = localtime();
    return sprintf('%04d%02d%02d%02d%02d%02d', $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0]);
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

sub extract_substrings {
    my ($texts) = @_;
    my %extracts;

    state %token;
    unless (%token) {
        for my $fn (glob('etc/substr-*.txt')) {
            my $token_type = substr($fn, 11, -4);
            my @tokens = uniqstr map { split /\t+/ } @{ read_string_list($fn) };
            for (@tokens) {
                push @{$token{$_}}, $token_type;
            }
        }
    }

    my @tokens = sort { length($b) <=> length($a) } keys %token;
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
        if (my $meta_el = $dom->find("meta[http-equiv=Content-Type]")->first) {
            ($charset) = $meta_el->{content} =~ m{charset=([^\s;]+)};
            $charset = lc($charset) if defined($charset);
        }
    }
    $charset = 'utf-8-strict' if $charset && $charset =~ /utf-?8/i;

    if (!$charset) {
        my $enc = guess_encoding($tx->res->body, qw/big5 utf8/);
        $charset = $enc->name if $enc;
    }

    unless ($charset) {
        # err "[$$] Unknown charset";
        return;
    }

    return $charset;
}

1;
