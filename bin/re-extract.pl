#!/usr/bin/env perl
use v5.26;
use strict;
use warnings;

use MCE;
use MCE::Loop;
use Getopt::Long qw(GetOptions);
use JSON::PP qw(encode_json decode_json);
use Try::Tiny;

use Sn;
use Sn::Seen;
use Sn::Extractor;

sub process {
    my ($f_input, $f_output) = @_;

    open my $fh_in, '<', $f_input;
    open my $fh_out, '>', $f_output;

    while(<$fh_in>) {
        chomp;
        my $json = $_;
        my $article = try { decode_json($json) } or next;
        next unless $article->{title} && $article->{content_text};

        $article->{substrings} = Sn::extract_substrings([ $article->{title}, $article->{content_text} ]);
        $article->{t_extracted} = 0+ time();

        my $x = encode_json($article) . "\n";
        print $fh_out $x;
    }

    close($fh_in);
    close($fh_out);

    return 0;
}

## main
my @article_files;
my %opts;
GetOptions(
    \%opts,
    "db|d=s"
);

if (@ARGV) {
    @article_files = @ARGV;
} else {
    die "--db <DIR> is needed" unless $opts{db} && -d $opts{db};
    @article_files = glob($opts{db} . "/articles-*.jsonl");
}

MCE::Loop::init { chunk_size => 'auto' };

mce_loop {
    for my $input (@$_) {
        my $output = $input . ".new";
        my ($error) = process($input, $output);
        if (!$error) {
            unlink($input);
            rename($output, $input);
        }
    }
} @article_files;
