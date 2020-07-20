#!/usr/bin/env perl
use Sn;

use Getopt::Long qw(GetOptions);
use PerlIO::via::gzip;

## main
my %opts;
GetOptions(
    \%opts,
    "force|f",
    "db|d=s",
);
die "--db <DIR> is needed" unless  $opts{db} && -d $opts{db};

my $this_yyyymm = do {
    my ($now_yyyy, $now_mm) = (localtime())[5,4];
    $now_mm += 1;
    $now_yyyy += 1900;
    sprintf '%04d%02d', $now_yyyy, $now_mm;
};

for my $table (qw(articles)) {
    my %buckets;
    for my $file (glob "$opts{db}/${table}-*.jsonl.gz") {
        my ($k) = $file =~ m/ - ([0-9]{6})[0-9]{2} \.jsonl\.gz \z/x;
        next unless $k && $k ne $this_yyyymm;
        push @{$buckets{$k}}, $file;
    }

    for my $yyyymm (keys %buckets) {
        my $output = $opts{db} . "/${table}-$yyyymm.jsonl.gz";
        next if -f $output;

        my $output_part = $output . ".part";
        open my $fh, '>:via(gzip)', $output_part;

        for my $input (@{$buckets{$yyyymm}}) {
            open my $infh, '<:via(gzip)', $input;
            while (<$infh>) {
                print $fh $_;
            }
            close($infh);
        }
        close($fh);

        unlink(@{$buckets{$yyyymm}});
        link($output_part, $output);
        unlink($output_part);
    }
}
