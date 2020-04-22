#!/usr/bin/env perl
use v5.26;
use warnings;
use JSON;
use Getopt::Long qw(GetOptions);

## main
my %opts;
GetOptions(
    \%opts,
    "yes",
);

for my $file (@ARGV) {
    next unless $file =~ m/articles-([0-9]{8})\.jsonl\z/;
    my $yyyymmdd = $1;

    my %buckets;
    open my $fh, '<:utf8', $file;
    while(<$fh>) {
        chomp;
        my $line = $_;

        my $x;
        eval {
            $x = JSON->new->decode($line);
            1;
        } or do {
            warn "Error: $@\n";
        };
        next unless $x;

        my $content_text_length = length($x->{content_text});

        push @{$buckets{$content_text_length}}, $x;
    }
    close($fh);

    my $wip_file = "/tmp/deduplicated-articles-$yyyymmdd.jsonl";
    open $fh, '>:utf8', $wip_file;

    for my $len (keys %buckets) {
        my @deduped;
        my @articles = sort { length($a->{url}) <=> length($b->{url}) } @{$buckets{$len}};

        while (@articles) {
            my $a0 = shift @articles;

            @articles = grep {
                $a0->{title} ne $_->{title} or $a0->{content_text} ne $_->{content_text}
            } @articles;

            push @deduped, $a0;
        }

        for (@deduped) {
            my $line = JSON->new->canonical->encode($buckets{$len}[0]);
            say $fh $line;
        }
    }

    close $fh;

    if ($opts{yes}) {
        unlink $file;
        rename $wip_file, $file;
    } else {
        say "DONE: $file => $wip_file";
    }
}
