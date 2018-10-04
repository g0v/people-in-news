#!/usr/bin/env perl
use v5.26;
use strict;
use warnings;
use Encode qw(encode_utf8 decode_utf8);
use Getopt::Long qw(GetOptions);
use JSON qw(decode_json);

sub sort_by(&@) {
    my $cb = shift;
    return map { $_->[1] } sort { $a->[0] cmp $b->[0] } map {[ $cb->($_), $_ ]} @_;
}

sub uniq_by(&@) {
    my $cb = shift;
    my %seen;
    my @items;
    for my $item (@_) {
        local $_ = $item;
        my $k = $cb->($item);
        unless ($seen{$k}) {
            $seen{$k} = 1;
            push @items, $item;
        }
    }
    return @items;
}

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
    for my $d (sort_by { -1 * length($d->{title}) } uniq_by { $_->{url} } @{$page{$h}}) {
        $d->{title} =~ s/\A\s+//;
        $d->{title} =~ s/\s+\z//;
        $md .= "- [$d->{title}]($d->{url})\n";
    }
    $md .= "\n";
}

my @t = localtime();
my $timestamp = sprintf('%04d%02d%02d%02d%02d%02d', $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0]);

my $output = $opts{o} . "/people-in-news-${timestamp}.md";
open my $fh, '>', $output;
say $fh encode_utf8($md);
