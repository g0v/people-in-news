#!/usr/bin/env perl
use v5.26;
use strict;
use warnings;

use MCE;
use MCE::Loop;
use Getopt::Long qw(GetOptions);
use JSON::PP qw(encode_json decode_json);

use Sn;
use Sn::Seen;
use Sn::KnownNames;

sub extract_names {
    my ($texts) = @_;
    state $kn = Sn::KnownNames->new( input => [  glob('etc/substr-*.txt') ] );

    my @extracted;
    for my $name (@{$kn->known_names}) {
        for my $txt (@$texts) {
            if (index($txt, $name) >= 0) {
                push @extracted, $name;
                last;
            }
        }
    }
    return \@extracted;
}

sub process {
    my ($f_input, $f_output) = @_;

    open my $fh_in, '<', $f_input;
    open my $fh_out, '>', $f_output;

    while(<$fh_in>) {
        chomp;

        my $article = decode_json($_);
        next unless $article->{title} && $article->{content_text};

        $article->{names} = extract_names([ $article->{title}, $article->{content_text} ]);
        $article->{t_extracted} = 0+ time();

        my $x = encode_json($article) . "\n";
        print $fh_out $x;
    }

    close($fh_in);
    close($fh_out);

    return 0;
}

## main
my %opts;
GetOptions(
    \%opts,
    "db|d=s"
);
die "--db <DIR> is needed" unless $opts{db} && -d $opts{db};

MCE::Loop::init { chunk_size => 'auto' };

my @article_files = glob($opts{db} . "/articles-*.jsonl");

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
