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

my @things = sort {
    $b->{mtime} <=> $a->{mtime}
} map {
    my $input = $_;
    my $output = $opts{o} . '/' . (basename($input) =~ s/\.md\z/.html/r);
    my $input_mtime = (stat($input))[7];
    ( (-f $output) && ($input_mtime <= (stat($output))[7]) ) ? () : (+{
        input => $input, output => $output, mtime => $input_mtime
    })
} glob("$opts{i}/*.md");

for (@things){
    my $input = $_->{input};
    my $output = $_->{output};

    say "$input => $output";
    my $text = decode_utf8( scalar read_file($input) );
    my $html = '<html><body>' . markdown($text) . '</body></html>';
    write_file($output, encode_utf8($html));
}
