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

my $this_yyyy = (localtime())[5] + 1900;

for my $table (qw(articles)) {
    my %buckets;
    for my $file (glob "$opts{db}/${table}-*.jsonl.gz") {
        my ($k) = $file =~ m/ - ([0-9]{4})[0-9]+\.jsonl\.gz \z/x;
        next unless $k && $k ne $this_yyyy;
        push @{$buckets{$k}}, $file;
    }

    for my $yyyy (keys %buckets) {
        my $output = $opts{db} . "/${table}-$yyyy.jsonl.gz";
        next if -f $output;

        my $output_part = $output . ".part";
        open my $fh, '>:via(gzip)', $output_part;

        for my $input (@{$buckets{$yyyy}}) {
            open my $infh, '<:via(gzip)', $input;
            while (<$infh>) {
                print $fh $_;
            }
            close($infh);
        }
        close($fh);

        unlink(@{$buckets{$yyyy}});
        link($output_part, $output);
        unlink($output_part);
    }
}
