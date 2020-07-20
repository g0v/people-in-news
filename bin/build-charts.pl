#!/usr/bin/env perl
use Sn;

use Getopt::Long qw(GetOptions);
use File::Next;
use File::Slurp qw(read_file);

use Encode qw(encode_utf8 decode_utf8);

sub build_chart_csv {
    my ($dataset, $dates, $stats, $output_fn) = @_;

    open my $fh, '>', $output_fn;

    say $fh join(",", $dataset, @$dates);
    for my $metric_name (keys %$stats) {
        say $fh encode_utf8(
            join(",", $metric_name, (map { $stats->{$metric_name}[$_] // "0" } (0..$#$dates)))
        );
    }

    close $fh;
}

## main
my %opts;
GetOptions(
    \%opts,
    "db=s",
    "o=s",
);
die "--db <DIR> is needed" unless -d $opts{db};
die "-o <DIR> is needed" unless -d $opts{o};

my %stats_file;
my $files = File::Next::files({ sort_files => 1, file_filter => sub { /dailystats-.+\.tsv/ } }, $opts{db});
while(my $file = $files->()) {
    my ($dataset, $date) = $file =~ m/dailystats - (.+) - ([0-9]{8}) \.tsv \z/x;
    push @{ $stats_file{$dataset} }, [ $date, $file ];
}

for my $dataset (keys %stats_file) {
    my %stats;

    my @dates = map { $_->[0] } @{ $stats_file{$dataset} };
    my %date_index = map { $dates[$_] => $_ } 0..$#dates;

    for (@{ $stats_file{$dataset} }) {
        my ($date, $fn) = @$_;
        my $i_date = $date_index{$date};
        for ( read_file($fn) ) {
            chomp;
            my @cols = split /\t/, decode_utf8($_);
            $stats{$cols[0]}[$i_date] = 0+$cols[1];
        }
    }

    build_chart_csv(
        $dataset,
        \@dates,
        \%stats,
        $opts{o} . "/chart-${dataset}.csv",
    );
}
