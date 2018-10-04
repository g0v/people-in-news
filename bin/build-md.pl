#!/usr/bin/env perl
use v5.26;
use strict;
use warnings;
use Encode qw(encode_utf8 decode_utf8);
use Getopt::Long qw(GetOptions);
use JSON qw(decode_json);

## main
my %opts;
GetOptions(
    \%opts,
    "o=s",
    "i=s",
);
die "-i <DIR> is needed" unless -d $opts{i};
die "-o <DIR> is needed" unless -d $opts{o};

my %page;
my @input = glob "$opts{i}/*.jsonl";
for my $file (@input) {
    open my $fh, '<', $file;
    while (<$fh>) {
        chomp;
        my $d = decode_json($_);
        next unless @{$d->{names}};
        my $header = join ',', sort { $a cmp $b } @{$d->{names}};
        push @{$page{$header}}, $d;
    }
    close($fh);
}

my $md = "";
for my $h (sort { length($a) <=> length($b) || $a cmp $b } keys %page) {
    $md .= "## $h\n\n";
    for my $d (@{$page{$h}}) {
        $d->{title} =~ s/\A\s+//;
        $d->{title} =~ s/\s+\z//;
        $md .= "- [$d->{title}]($d->{url})\n";
    }
    $md .= "\n";
}

say encode_utf8($md);
