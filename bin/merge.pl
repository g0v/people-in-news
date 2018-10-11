#!/usr/bin/env perl
use v5.26;
use strict;
use warnings;
use Getopt::Long qw(GetOptions);

use File::Basename qw(basename);
use Encode qw(encode_utf8 decode_utf8);
use JSON qw(decode_json);

## main
my %opts;
GetOptions(
    \%opts,
    "force|f",
    "o=s",
    "i=s",
);
die "-i <DIR> is needed" unless -d $opts{i};
die "-o <DIR> is needed" unless -d $opts{o};

my %buckets;
for my $file (glob "$opts{i}/*.jsonl") {
    my ($k) = $file =~ m/ - ([0-9]{8}) ([0-9]{6})? \.jsonl \z/x;
    next unless $k;
    push @{$buckets{$k}}, $file;
}

for my $yyyymmdd (keys %buckets) {
    my $out = '';
    for my $input (@{$buckets{$yyyymmdd}}) {
        local $/;
        open my $fh, '<', $input;
        $out .= <$fh>;
        close($fh);
    }

    my $output = $opts{o} . "/daily-$yyyymmdd.jsonl";
    my $output_temp = $output . '.temp';
    open my $fh, '>', $output_temp;
    print $fh $out;
    close($fh);

    unlink(@{$buckets{$yyyymmdd}});
    link($output_temp, $output);
    unlink($output_temp);
}
