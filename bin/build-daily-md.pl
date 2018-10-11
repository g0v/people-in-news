#!/usr/bin/env perl
use v5.26;
use strict;
use warnings;
use File::Basename qw(basename);
use Encode qw(encode_utf8 decode_utf8);
use Getopt::Long qw(GetOptions);
use JSON qw(decode_json);
use List::Util qw(maxstr);

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

sub build_md {
    my ($page, $output) = @_;

    my $md = "";
    for my $h (sort { $a cmp $b } keys %$page) {
        $md .= "## $h\n\n";
        for my $d (uniq_by { $_->{content_text} } @{$page->{$h}}) {
            $d->{title} =~ s/\A\s+//;
            $d->{title} =~ s/\s+\z//;
            $md .= "- [$d->{title}]($d->{url})\n";
        }
        $md .= "\n";
    }

    $md =~ s/[^[:print:]\s]//g;

    open my $fh, '>', $output;
    say $fh encode_utf8($md);
    close($fh);
}

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

my @t = localtime();
my $today = sprintf('%04d%02d%02d', $t[5]+1900, $t[4]+1, $t[3]);
my $daily_today = $opts{o} . "/daily-$today.md";

for my $yyyymmdd (keys %buckets) {
    my @input = @{$buckets{$yyyymmdd}};
    my $output = $opts{o} . "/daily-$yyyymmdd.md";
    next if !$opts{force} && (($output lt $daily_today) && (-f $output));

    my %page;

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
    
    build_md(\%page, $output);
}

my $new_index = maxstr( glob "$opts{o}/daily-*.md" );
unlink("$opts{o}/Home.md");
link($new_index, "$opts{o}/Home.md");
