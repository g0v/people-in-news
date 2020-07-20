#!/usr/bin/env perl
use Sn;

use Getopt::Long qw(GetOptions);
use Encode qw(encode_utf8 decode_utf8);
use JSON qw(decode_json);
use MCE::Loop;

use Importer 'Text::Util::Chinese' => qw( tokenize_by_script );

sub sort_by(&@) {
    my ($cb, $things);
    return map {
        $_->[1]
    } sort {
        $b->[0] <=> $a->[0]
    } map {
        [$cb->(), $_]
    }@$things;
}

sub find_names {
    my ($jsonline, $titles) = @_;

    my %freq;
    my $data = decode_json($jsonline);

    my @segments = (
        tokenize_by_script( $data->{content_text} ),
        tokenize_by_script( $data->{title} ),
    );

    my $name_re = qr(\p{Letter}{2,6});
    my $title_re = '(?:' . join('|', map { quotemeta}  sort { length($b) <=> length($a) } @$titles) . ')';
    for my $seg (@segments) {
        my @parts = split /($title_re)/, $seg;
        if (@parts > 1) {
            say encode_utf8(join ' ', map { "<$_>" } @parts);
        }

        # while ($seg =~ m{($name_re)?($title_re)($name_re)?}g) {
        #     my ($name1, $title, $name2) = ($1//'', $2, $3//'');
        #     if ($name1) {
        #         $freq{front}{$name1}++;
        #         $freq{title}{$name1}{$title}++;
        #     }
        #     if ($name2) {
        #         $freq{back}{$name2}++;
        #         $freq{title}{$name2}{$title}++;
        #     }
        #     say encode_utf8("$seg >>> <$name1> $title <$name2>");
        # }
    }
    MCE->gather(\%freq);
}

## main
my %opts;
GetOptions(
    \%opts,
    "force|f",
    "o=s",
    "i=s",
);
die "-i <DIR> is needed" unless -d $opts{i};

my @titles = do {
    open my $fh, '<', 'etc/title.txt';
    grep { $_ ne '' } map { chomp; decode_utf8($_) } <$fh>;
};

MCE::Loop::init { chunk_size => 1 };
my %freq;
for my $file (glob "$opts{i}/*.jsonl") {
    my @o = mce_loop_f { find_names($_, \@titles) } $file;
    for my $f (@o) {
        for my $x (qw(front back)) {
            for (keys %{$f->{$x}}) {
                $freq{$x}{$_} += $f->{$x}{$_};
            }
        }
        for my $k1 (keys %{$f->{title}}) {
            for my $k2 (keys %{$f->{title}{$k1}}) {
                $freq{title}{$k1}{$k2} += $f->{title}{$k1}{$k2};
            }
        }
    }
}

my @names;
for my $n (keys %{$freq{front}}) {
    if ($freq{front}{$n} > 2 && $freq{back}{$n} && $freq{back}{$n} > 2) {
        push @names, $n;
    }
}

for my $n (sort {  $freq{front}{$b} <=> $freq{front}{$a} || $freq{back}{$b} <=> $freq{back}{$a} } @names) {
    my $titles = join ",", (keys %{$freq{title}{$n}});
    say encode_utf8($n . "\t" . $freq{front}{$n} . "\t" . $freq{back}{$n} . "\t" . $titles);
}
