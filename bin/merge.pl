#!/usr/bin/env perl
use Sn;

use Getopt::Long qw(GetOptions);

## main
my %opts;
GetOptions(
    \%opts,
    "force|f",
    "db|d=s",
);
die "--db <DIR> is needed" unless  $opts{db} && -d $opts{db};

for my $table (qw(articles)) {
    my %buckets;
    for my $file (glob "$opts{db}/${table}-*.jsonl") {
        my ($k) = $file =~ m/ - ([0-9]{8}) ([0-9]{6})? (-[0-9]+)? \.jsonl \z/x;
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

        my $output = $opts{db} . "/${table}-$yyyymmdd.jsonl";
        my $output_temp = $output . '.temp';
        open my $fh, '>', $output_temp;
        print $fh $out;
        close($fh);

        unlink(@{$buckets{$yyyymmdd}});
        link($output_temp, $output);
        unlink($output_temp);
    }
}
