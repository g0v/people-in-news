#!/usr/bin/env perl
use Sn;

use Getopt::Long qw(GetOptions);
use JSON::SL;
use Encode qw(encode_utf8);

## main
my %opts;
GetOptions(
    \%opts,
    "moedict=s",
);
die "Require a path of dict-revised.json with `--moedict <PATH>`" unless $opts{moedict} && -f $opts{moedict};

open my $fh, '<:utf8', $opts{moedict};
my $json = JSON::SL->new;
$json->set_jsonpointer([ '/^/title' ]);

open my $fh_out, '>', "etc/lexiconn-moedict.txt" ;
my $txt = '';
while (read($fh, $txt, 4096)) {
    for my $result ( $json->feed($txt) ) {
        my $x = $result->{Value};
        next if index($x, '{[') >= 0;

        $x =~ s/\A(\p{Han}+) \( \P{Han}+ \)\z/$1/x;
        $x =~ s/\A(\p{Han}+) （ \P{Han}+ ）\z/$1/x;

        next if length($x) == 1 || $x =~ /\P{Han}/;

        say $fh_out encode_utf8($x);
    }
}
