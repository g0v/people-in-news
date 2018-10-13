#!/usr/bin/env perl
use v5.26;
use strict;
use warnings;
use Getopt::Long qw(GetOptions);

use List::Util qw(uniq);
use File::Basename qw(basename);
use Encode qw(encode_utf8 decode_utf8);
use JSON qw(decode_json);
use MCE::Loop;

sub sort_by(&@) {
    my ($cb, $things);
    return map {
        $_->[1]
    } sort {
        $b->[0] <=> $a->[0]
    } map {
        [$cb->(), $_]
    }@$things;
}

sub find_names {
    my ($jsonline, $titles) = @_;

    my %freq;
    my $data = decode_json($jsonline);
    my $name_re = qr(\p{Letter}{2,6});
    for my $t (@$titles) {
        for my $n (($data->{title} =~ m/($name_re)\Q$t\E/g), ($data->{content_text} =~ m/($name_re)$t/g)) {
            $freq{front}{$n}++;
            $freq{title}{$n}{$t}++;
        }
        for my $n (($data->{title} =~ m/\Q$t\E($name_re)/g),($data->{content_text} =~ m/\Q$t\E($name_re)/g)) {
            $freq{back}{$n}++;
            $freq{title}{$n}{$t}++;
        }
    }
    MCE->gather(\%freq);
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

my @titles = do {
    open my $fh, '<', 'etc/title.txt';
    map { chomp; decode_utf8($_) } <$fh>;
};

MCE::Loop::init { chunk_size => 1 };
my %freq;
for my $file (glob "$opts{i}/*.jsonl") {
    my @o = mce_loop_f { find_names($_, \@titles) } $file;
    for my $f (@o) {
        for my $x (qw(front back)) {
            for (keys %{$f->{$x}}) {
                $freq{$x}{$_} += $f->{$x}{$_};
            }
        }
        for my $k1 (keys %{$f->{title}}) {
            for my $k2 (keys %{$f->{title}{$k1}}) {
                $freq{title}{$k1}{$k2} += $f->{title}{$k1}{$k2};
            }
        }
    }
}

my @names;
for my $n (keys %{$freq{front}}) {
    if ($freq{front}{$n} > 2 && $freq{back}{$n} && $freq{back}{$n} > 2) {
        push @names, $n;
    }
}

for my $n (sort {  $freq{front}{$b} <=> $freq{front}{$a} || $freq{back}{$b} <=> $freq{back}{$a} } @names) {
    my $titles = join ",", (keys %{$freq{title}{$n}});
    say encode_utf8($n . "\t" . $freq{front}{$n} . "\t" . $freq{back}{$n} . "\t" . $titles);
}
