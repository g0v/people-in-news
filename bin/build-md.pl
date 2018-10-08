#!/usr/bin/env perl
use v5.26;
use strict;
use warnings;
use File::Basename qw(basename);
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

sub build_md {
    my ($page, $output) = @_;

    my $md = "";
    for my $h (sort { length($a) <=> length($b) || $a cmp $b } keys %$page) {
        $md .= "## $h\n\n";
        for my $d (sort_by { -1 * length($_->{title}) } uniq_by { $_->{url} } @{$page->{$h}}) {
            $d->{title} =~ s/\A\s+//;
            $d->{title} =~ s/\s+\z//;
            $md .= "- [$d->{title}]($d->{url})\n";
        }
        $md .= "\n";
    }

    open my $fh, '>', $output;
    say $fh encode_utf8($md);
    close($fh);
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

my @input = glob "$opts{i}/*.jsonl";
for my $file (@input) {
    my $output = $opts{o} . '/' . ( basename($file) =~ s/\.jsonl$/.md/r );
    next if -f $output;

    my %page;

    open my $fh, '<', $file;
    while (<$fh>) {
        chomp;
        my $d = decode_json($_);
        next unless @{$d->{names}};
        my $header = join ',', sort { $a cmp $b } @{$d->{names}};
        push @{$page{$header}}, $d;
    }
    close($fh);

    build_md(\%page, $output);
}
