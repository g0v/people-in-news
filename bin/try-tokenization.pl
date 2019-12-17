#!/usr/bin/env perl
use v5.18;
use strict;
use warnings;


use JSON::SL;
use List::Util qw(first);

use Text::Util::Chinese qw( tokenize_by_script );
use File::Glob ':bsd_blob';
use FindBin '$Bin';
use Sn::ArticleIterator;

sub load_lexiconns {
    bsd_glob("$Bin/../etc/dict-*.txt"), bsd_glob("$Bin/../etc/lexiconn-*.txt"),
}

sub load_moedict {
    open my $fh, '<:utf8', "$ENV{HOME}/Projects/g0vtw/moedict-data/dict-revised.json";
    my $json = JSON::SL->new;
    $json->set_jsonpointer([ '/^/title' ]);

    my $txt = '';
    my $maxl = 0;
    my %dict;
    while (read($fh, $txt, 4096)) {
        for my $result ( $json->feed($txt) ) {
            my $x = $result->{Value};
            next if $x =~ /\p{Punct}/;
            my $len = length($x);
            next unless 2 <= $len && $len <= 4;
            $dict{$x} = 1;
            $maxl = $len if ($maxl < $len);
        }
    }

    say "Moedict loaded";
    return \%dict;
}

my $in_dict = load_moedict;

my $articles = Sn::ArticleIterator->new(
    filter_file => sub { /\.jsonl.gz$/ },
    db_path => "var/db"
);

binmode STDOUT, ":utf8";
while (my $article = $articles->()) {
    my (@tokens, $offset);
    for my $seg ( tokenize_by_script( $article->{content_text} ) ) {
        @tokens = ();
        if ($seg =~ /^\p{Han}/) {
            my $offset = 0;
            while ($offset < length($seg)) {
                my $tok = first {
                    $in_dict->{$_}
                } map {
                    substr($seg, $offset, $_)
                } (4,3,2);

                $tok ||= substr($seg, $offset, 1);
                $offset += length($tok);

                push @tokens, $tok;
            }
        } else {
            @tokens = ($seg);
        }
        say ">> " . join(" ", @tokens);
    }
}
