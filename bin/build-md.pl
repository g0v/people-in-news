#!/usr/bin/env perl
use Sn;
use Importer 'Sn::Util' => qw( nsort_by sort_by uniq_by );

use File::Basename qw(basename);
use Encode qw(encode_utf8);
use Getopt::Long qw(GetOptions);
use JSON qw(decode_json);
use List::Util qw(maxstr);

sub build_md {
    my ($page, $output) = @_;

    my $md = "";
    for my $h (nsort_by { -1 * @{$page->{$_}} } keys %$page) {
        $md .= "## $h\n\n";
        for my $d (sort_by { -1 * length($_->{title}) } uniq_by { $_->{content_text} } sort_by { length($_->{url}) } @{$page->{$h}}) {

            my $hashtags = join(
                " ",
                map { "#" . $_ }
                sort { $a cmp $b }
                map { @{$d->{substrings}{$_}} }
                grep { $_ ne "people" }
                (keys %{$d->{substrings}})
            );

            $d->{title} =~ s/\A\s+//;
            $d->{title} =~ s/\s+\z//;
            $md .= "- [$d->{title}]($d->{url}) $hashtags\n";
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
        for my $name (@{$d->{substrings}{people} //[]}) {
            push @{$page{$name}}, $d;
        }
    }
    close($fh);

    build_md(\%page, $output);
}
