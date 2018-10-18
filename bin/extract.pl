use v5.26;
use strict;
use warnings;
use Getopt::Long qw(GetOptions);

use File::Basename qw(basename);
use Encode qw(decode encode_utf8 decode_utf8);
use JSON qw(encode_json decode_json);
use List::Util qw(maxstr);

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
    my ($context) = @_;

    my @jsonlines;
    open my $fh, '<', $context->{input};
    @jsonlines = map { chomp; $_ } <$fh>;
    close($fh);

    open $fh, '>', $context->{output};
    for (@jsonlines) {
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
                t_extracted => (0+ time()),
            }) . "\n";

            print $fh $line;
        }
    }
    close($fh);
}

## main
my %opts;
GetOptions(
    \%opts,
    "force|f",
    "db|d=s",
);
die "--db <DIR> is needed" unless -d $opts{db};

my $kn = Sn::KnownNames->new( input => [  glob('etc/substr-*.txt') ] );

mce_loop {
    for(@$_) {
        process($_)
    }
} grep {
    ! -f $_->{output}
} map {
    my $input = $_;
    my $output = $input =~ s/articles/extracts/r;
    +{
        known_names => $kn->known_names,
        output => $output,
        input  => $input,
    }
} grep {
    m/articles - ([0-9]{8})([0-9]{6})? \.jsonl \z/x
} (glob "$opts{db}/*.jsonl");
