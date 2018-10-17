#!/usr/bin/env perl
use v5.26;
use strict;
use warnings;
use File::Basename qw(basename);
use Getopt::Long qw(GetOptions);
use Text::Markdown::Discount qw(markdown);
use Encode qw(decode_utf8 encode_utf8);
use File::Slurp qw(read_file write_file);
use MCE::Loop;

## main
my %opts;
GetOptions(
    \%opts,
    "force|f",
    "i=s",
    "o=s",
);
die "-i <DIR> is needed" unless -d $opts{i};
die "-o <DIR> is needed" unless -d $opts{o};

Text::Markdown::Discount::with_html5_tags();

MCE::Loop::init { chunk_size => 1 };
mce_loop {
    my ($input, $output) = @$_;

    say "$input => $output";
    my $text = decode_utf8( scalar read_file($input) );
    my $html = '<html><body>' . markdown($text) . '</body></html>';
    write_file($output, encode_utf8($html));

} sort {
    $b->[2] <=> $a->[2]
} map {
    my $input = $_;
    my $output = $opts{o} . '/' . (basename($input) =~ s/\.md\z/.html/r);
    (-f $output) ? () : [$input, $output, (stat($input))[7]]
} glob("$opts{i}/*.md");
