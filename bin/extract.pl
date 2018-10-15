use v5.26;
use strict;
use warnings;
use Getopt::Long qw(GetOptions);

use File::Basename qw(basename);
use Encode qw(decode encode_utf8 decode_utf8);
use JSON qw(encode_json decode_json);

use MCE::Loop;

use Sn;
use Sn::KnownNames;

sub extract_names {
    my ($known_names, $texts) = @_;
    my @extracted;
    for my $name (@$known_names) {
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
    my ($context, $input) = @_;

    my @jsonlines;
    open my $fh, '<', $input;
    @jsonlines = map { chomp; $_ } <$fh>;
    close($fh);

    mce_loop {
        my ($mce, $chunk_ref, $chunk_id) = @_;

        for(@{$chunk_ref}) {
            my $article = decode_json($_);
            my @texts = ($article->{title}, $article->{content_text});
            my $names = extract_names(
                $context->{known_names},
                \@texts,
            );
            if (@$names) {
                my $line = encode_json({
                    names => $names,
                    url => $article->{url},
                    title => $article->{title},
                }) . "\n";
                MCE->sendto("file:" . $context->{output}, $line);
            }
        }
    } @jsonlines;
}

## main
my %opts;
GetOptions(
    \%opts,
    "force|f",
    "db|d=s",
);
die "--db <DIR> is needed" unless -d $opts{db};

my @input = grep {
    m/articles - ([0-9]{8}) \.jsonl \z/x
} (glob "$opts{db}/*.jsonl");

my $kn = Sn::KnownNames->new( input => [  glob('etc/people*.txt') ] );

my $output = $opts{db} . "/extracts-" . Sn::ts_now() . ".jsonl";

for(@input) {
    process({
        known_names => $kn->known_names,
        output => $output
    }, $_);
}
